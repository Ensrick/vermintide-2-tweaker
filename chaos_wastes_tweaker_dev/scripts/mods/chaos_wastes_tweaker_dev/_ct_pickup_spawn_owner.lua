--[[
_ct_pickup_spawn_owner — pickup spawn IDENTITY and payout (#1159 / #2 file-size refactor).

RESPONSIBILITY
Owns every "what unit actually materializes at this spawn seam, and what does it
pay out" decision on the host:
  * collectible -> Pilgrim's Coin identity rewrite at PickupSystem._spawn_pickup
    (loot_die / lorebook_page / painting_scrap on injected adventure levels, #134/#351)
  * the same rewrite at the UnitSpawner.spawn_network_unit bypass chest loot dice
    take instead of PickupSystem (#351)
  * the #294 non-resident pickup-unit residency guard on the spawn chokepoint
  * the book-pedestal ladder in PickupSystem._spawn_guaranteed_pickup:
    Chest of Trials (cap-budgeted, incl. natively baked deus_cursed_chest
    spawners, #60) -> Belakor locus -> big coin casket -> empty
  * the big-casket 3x payout on GameModeDeus._get_coins_amount_and_type
  * the #58/#143 census probes those seams carry (spawn-type source split,
    grenade-pool tally, collectible gate breakdown)

Extracted VERBATIM from chaos_wastes_tweaker_dev.lua with no behaviour change.
mod:dofile is not a singleton — the entry calls it EXACTLY once, at the exact
point this block previously executed, so hook-registration order, the load-time
provenance markers, and the [ct-probe] receipt ordering keep their original
timing.

COMPOSES WITH, DOES NOT OVERLAP, _ct_spawn_eligibility_owner.lua
That module owns the orthogonal question — "MAY this pickup claim this spawner?"
(PickupSystem._can_spawn, the career-exclusive blocklist, the coin-reservation
partition, the unit-loadability pre-flight). It installs immediately AFTER this
one in the entry. The two share no hook and no helper: eligibility decides which
spawners a pickup type may consume, this module decides what the consumed
spawner then produces.

HOOKS OWNED (each hooked EXACTLY ONCE in the whole mod — VMF silently drops a
second hook on the same Class/method pair):
  PickupSystem._spawn_pickup            (full hook, two-value return, #322)
  UnitSpawner.spawn_network_unit        (full hook)
  PickupSystem._spawn_guaranteed_pickup (full hook)
  GameModeDeus._get_coins_amount_and_type (full hook)

CROSS-FILE CONTRACT (unchanged by the move)
  * Entry helpers are reached through the mod._ct_* seams the entry publishes
    BEFORE this module loads: mod._ct_effective_setting (entry ~2646),
    mod._ct_on_injected_adventure_level / mod._ct_adventure_base_from_level_key
    (entry ~5096), mod._ct_curse_lighting_owner.current_node_is_belakor
    (entry ~6069). `_dbg` is the same mod:debug wrapper the entry uses.
  * The two PER-LEVEL counters are now `mod` fields, not file-locals:
    mod._ct_chest_conversions_this_level and
    mod._ct_belakor_altar_spawned_this_level. They were entry locals only so the
    populate_pickups hook (lexically EARLIER, and the sole reset site) could bind
    them at closure-creation time. With the readers in a separate chunk that
    lexical trick no longer reaches, so they move onto `mod` — the same escape
    hatch the entry already uses for cross-chunk mutable state (see
    mod._ct_pending_team_teleport). populate_pickups still owns the reset; this
    module still owns every increment. Values and reset timing are unchanged.
  * Load-time globals set here and asserted by /ct_regression_test in
    _ct_regression.lua: CT_MORGRIM143_MARKER, CT_MORGRIM143_RENORM_MARKER,
    CT_PICKUP_RESIDENCY_GUARD_MARKER, CT_SPAWN_PICKUP322_MARKER. They stay
    globals — the regression suite loads later and reads them bare.
  * Published on `mod` for the regression suite and the earlier census:
    mod._ct_collectible_policy, mod._ct_collectible_to_coin,
    mod._ct351_rewrite_network_spawn, mod._ct351_log_conversion, mod._ct134_log,
    mod._ct_morgrim143_count, mod._ct_morgrim143_grenade_tally,
    mod._ct_pickup_unit_spawn_safe.
  * mod._ct_tally_count (the #58/#156 spawn census, defined with the
    populate_pickups block in the entry) is resolved at CALL time here, so the
    census keeps counting the post-conversion pickup_name exactly as before.
]]

local mod = get_mod("ct_dev")

-- Behaviour-identical shims for the entry file-locals this block used before the
-- extraction. `_dbg` mirrors the entry's mod:debug wrapper (PROJECT_STANDARDS
-- § 3.6); the rest delegate to the mod._ct_* seams the entry publishes earlier in
-- its own chunk, so each call resolves to the exact same function object.
local function _dbg(fmt, ...)
    mod:debug("[ct:dbg] " .. fmt, ...)
end

local effective_setting = function(name)
    local f = mod._ct_effective_setting
    if f then return f(name) end
    return mod:get(name)
end

local function on_injected_adventure_level()
    return mod._ct_on_injected_adventure_level()
end

local function adventure_base_from_level_key(level_key)
    return mod._ct_adventure_base_from_level_key(level_key)
end

local function _current_node_is_belakor()
    return mod._ct_curse_lighting_owner.current_node_is_belakor()
end

-- Per-level counters shared with the entry's populate_pickups hook, which is the
-- SOLE reset site (it zeroes both at the top of every populate pass). See the
-- cross-file contract note in the header for why they are mod fields.

-- Hook on PickupSystem._spawn_pickup — the lowest-level spawn function for the
-- PickupSystem-owned paths (public spawn_pickup, spawn_pickup_async,
-- buff_spawn_pickup, _spawn_guaranteed_pickup, _spawn_spread_pickups). Chest
-- bonus dice bypass this class and are covered at UnitSpawner below (#351).
-- Used for two purposes:
--
-- 1. Substitute loot_die → deus_soft_currency on injected adventure levels.
--    The Bogenhafen loot-die system has no CW analogue. Catches:
--      a. Guaranteed spawners with loot_die data (also covered by our explicit
--         hook on _spawn_guaranteed_pickup above, but doesn't hurt to double-up).
--      b. Flow-event spawned loot dice (level-script-driven bonus dice drops).
--      c. Boss kill loot if the game_mode somehow returned "loot_die" (vanilla
--         GameModeDeus.get_boss_loot_pickup returns "deus_soft_currency" already
--         for our deus-mode adventure levels, but defensive).
--
-- 2. Disable physics collision on CW altars/chests so they don't block player
--    pathing at adventure spawner positions (designed for ammo/healing, not for
--    a multi-meter-wide blocking prop). `Actor.set_collision_enabled(false)`
--    removes the character-controller block; interaction raycasts still hit the
--    visible mesh, so E-to-open still works.
local _CW_BLOCKING_PICKUP_NAMES = {
    deus_weapon_chest = true,
    deus_cursed_chest = true,
    deus_02 = true,  -- alternate chest variant some CW level pickup_settings reference
}

-- Adventure-map collectibles with no CW analogue -> Pilgrim's Coin. loot_die
-- covers bonus dice AND the DLC-map "hidden mission" reskins (Bogenhafen ale,
-- Blightreaper Rugbrodder ale, Enchanter's Lair poison-feast chalice -- all
-- loot_die-tagged spawners of the same bonus-dice system). lorebook_page (the
-- lore-page collectible) is the only other map collectible type and has no CW
-- use, so it's converted too. Ravaged Art is `painting_scrap`; its guaranteed
-- level spawners bypass the spread-count replacement, so it must use this same
-- identity conversion rather than relying on pickup-settings counts.
mod._ct_collectible_policy = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_collectible_policy")
local _CW_COLLECTIBLE_TO_COIN = mod._ct_collectible_policy.CONVERT_TO_COIN
mod._ct_collectible_to_coin = _CW_COLLECTIBLE_TO_COIN  -- exposed for regression guard
mod._ct351_rewrite_network_spawn = mod._ct_collectible_policy.rewrite_network_spawn

do
    local emitted = {}
    function mod._ct351_log_conversion(source, original_name)
        local key = tostring(source) .. ":" .. tostring(original_name)
        local count = emitted[key] or 0
        if count >= 2 then return end
        emitted[key] = count + 1
        pcall(printf, "[ct:351] collectible_conversion source=%s original=%s final=deus_soft_currency authority=host count=%d",
            tostring(source), tostring(original_name), count + 1)
    end
end

-- #134/#351 verification receipt. Logs each collectible that reaches the
-- PickupSystem path with the injected-level gate breakdown. Chest-generated
-- Loot Dice bypass this function entirely and use the bounded [ct:351]
-- UnitSpawner receipt below. Raw printf survives mod-logging-off; bounded 80
-- lines/session; pcall-guarded.
do
    local _n = 0
    function mod._ct134_log(name, spawn_type)
        if _n >= 80 then return end
        _n = _n + 1
        local on_adv, deus, level_id, adv_base = false, false, "?", "?"
        -- v0.7.243-dev (#134): is_server added. The first capture (2026-06-27) was
        -- CLIENT-side and showed on_adv=false; the fix needs a HOST-side line to
        -- prove whether the injected-adventure gate is false only on the client
        -- (client IS_INJECTED divergence, #136 class) or on the host too (the gate
        -- itself is missing this injected base). is_server disambiguates the two.
        local is_server = false
        pcall(function()
            local cur = LevelHelper and LevelHelper:current_level_settings()
            level_id = (cur and cur.level_id) or "?"
            adv_base = tostring(adventure_base_from_level_key(level_id))
            local m = Managers.mechanism and Managers.mechanism.game_mechanism
                and Managers.mechanism:game_mechanism()
            deus = (m and m.get_deus_run_controller and m:get_deus_run_controller()) ~= nil
            on_adv = on_injected_adventure_level()
            is_server = (Managers and Managers.player and Managers.player.is_server) and true or false
        end)
        printf("[ct-probe:collectible] name=%s spawn_type=%s is_server=%s on_adv=%s in_coin_set=%s deus=%s level=%s adv_base=%s",
            tostring(name), tostring(spawn_type), tostring(is_server), tostring(on_adv),
            tostring(_CW_COLLECTIBLE_TO_COIN[name] and "yes" or "no"),
            tostring(deus), tostring(level_id), tostring(adv_base))
    end
end

-- ============================================================
-- #143 DIAGNOSTIC (read-only): Morgrim's Bomb appearance-by-source census
-- ============================================================
-- "Morgrim's Bomb" == holy_hand_grenade. spawn_type (arg to PickupSystem._spawn_pickup,
-- the single spawn chokepoint, pickup_system.lua:1208) is the source discriminator:
--   "spawner"    = world spread-pool sampler (the 0.8 spawn_weighting path; suspected
--                  #143 origin -- reducing it blind crashed the sampler in v0.7.143,
--                  reverted v0.7.145, so we MEASURE before renormalizing).
--   "guaranteed" = level-baked spawner.  "dropped" = drop_item_on_ability_use bomb-boon
--   drop (source c/#120/#101).  "buff" = buff_spawn_pickup.
-- The chokepoint catches boon drops too (they route through _spawn_pickup as "dropped"),
-- so this one probe splits world-weight appearances from boon-driven ones -- the exact
-- question #143 needs answered before a safe grenade-pool renormalization. printf
-- (mod:debug is silent with logging off); Morgrim's is infrequent so no flood.
-- Read-only: printf only.
CT_MORGRIM143_MARKER = "morgrim143:appearance_by_spawn_type_census_v0.7.212"
-- issue 511: load-time marker for the #143 sum-preserving grenade renorm FIX (the
-- actual over-spawn fix lives in the PickupSystem.populate_pickups hook). Replaces
-- the io.open self-grep that threw in the VMF sandbox (no `io`). The exact renorm
-- text is a source invariant flagged for a repo QA gate (PROJECT_STANDARDS 2.2b tier a).
CT_MORGRIM143_RENORM_MARKER = "morgrim143:holy_hand_grenade_sum_preserving_renorm_v0.7.232"
do
    local _by_source = {}
    mod._ct_morgrim143_count = function(spawn_type, on_adv)
        local k = tostring(spawn_type)
        _by_source[k] = (_by_source[k] or 0) + 1
        pcall(printf, "[ct:morgrim143] Morgrim's appeared: source=%s (x%d this session) injected_adv=%s",
            k, _by_source[k], tostring(on_adv))
    end

    -- v0.7.228-dev (#143 round 2): census ALL grenade-pool spawns, not just Morgrim's,
    -- so any log yields holy's true SHARE of world grenade spawns (the 2026-07-04 log
    -- proved the renorm applies -- holy 0.25 -> 0.125 on the CWV-normalized pool -- and
    -- only x2 spawner-holys all session; the perceived abundance must then come from
    -- grant-side faucets: blessing_holy_hand_grenade at the Shrine of Strife,
    -- drop_item_on_active_ability_use boon drops, altar/shop power-ups. Those are
    -- boon-trace / source=dropped territory, not spawn weight). Same chokepoint,
    -- printf-only, no new hook.
    local _grenade_names = {
        holy_hand_grenade = true, frag_grenade_t1 = true, fire_grenade_t1 = true,
        frag_grenade_t2 = true, fire_grenade_t2 = true, cwv_tuskgor_javelin_grenade = true,
    }
    local _grenade_counts, _grenade_total = {}, 0
    mod._ct_morgrim143_grenade_tally = function(pickup_name)
        if not _grenade_names[pickup_name] then return end
        _grenade_counts[pickup_name] = (_grenade_counts[pickup_name] or 0) + 1
        _grenade_total = _grenade_total + 1
        local parts = {}
        for n, c in pairs(_grenade_counts) do parts[#parts + 1] = string.format("%s=%d", n, c) end
        pcall(printf, "[ct:morgrim143] grenade world-spawn tally (session): total=%d { %s }",
            _grenade_total, table.concat(parts, ", "))
    end
end

-- #294 crash guard (exposed for /ct_regression_test). Returns whether it is SAFE to let
-- vanilla _spawn_pickup spawn this pickup's unit. FALSE only when the pickup names a unit
-- that is genuinely non-resident (would C-crash spawn_network_unit -> add_unit_extensions).
-- Mirrors vanilla PickupSystem._safe_to_spawn_pickup (pickup_system.lua:878). Fails SAFE
-- (returns true, i.e. does not block) when there's no named unit, when a spawn_override_func
-- handles spawning itself, or when Application.can_get is unavailable -- so the guard can
-- never false-drop a legitimate pickup, only stop a provably non-resident one.
CT_PICKUP_RESIDENCY_GUARD_MARKER = "spawn_pickup_can_get_unit_guard_v0.7.222"
function mod._ct_pickup_unit_spawn_safe(settings)
    local un = settings and settings.unit_name
    if not un then return true end                         -- no named unit -> not our concern
    if settings.spawn_override_func then return true end   -- custom spawn path, leave alone
    if not (rawget(_G, "Application") and Application.can_get) then return true end  -- can't check -> don't block
    return Application.can_get("unit", un) and true or false
end

mod:hook("PickupSystem", "_spawn_pickup", function(func, self, settings, pickup_name, position, rotation, flag, spawn_type, ...)
    local on_adv = on_injected_adventure_level()

    -- #134/#351: a collectible arriving here means it used PickupSystem; log
    -- its gate before the host-authoritative identity rewrite.
    if pickup_name == "loot_die" or pickup_name == "lorebook_page" or pickup_name == "painting_scrap" then
        mod._ct134_log(pickup_name, spawn_type)
    end

    local original_name = pickup_name
    local routed_name, converted = mod._ct_collectible_policy.route_name(
        pickup_name, on_adv, self.is_server == true)
    if converted then
        pickup_name = routed_name
        settings = (AllPickups and AllPickups.deus_soft_currency) or settings
        mod._ct351_log_conversion("pickup_system", original_name)
    end

    -- #294 (crash): guard the spawn chokepoint against a NON-RESIDENT pickup unit.
    -- _ct_pickup_unit_spawn_safe mirrors vanilla's own PickupSystem._safe_to_spawn_pickup
    -- (pickup_system.lua:878) can_get("unit", unit_name) check, which the _spawn_pickup
    -- path (pickup_system.lua:1414 -> spawn_network_unit at :1290) does NOT perform. A
    -- mutator pickup whose package isn't resident -- e.g. skulls_2023 'pup_skull_of_fury'
    -- force-spawned via the gt devtool without the mutator package loaded -- otherwise
    -- reaches spawn_network_unit non-resident and hard-crashes add_unit_extensions
    -- (entity_manager2.lua:114 "table index is nil"). Skip it, exactly as vanilla's
    -- _safe_to_spawn_pickup would (returns false -> no spawn).
    if not mod._ct_pickup_unit_spawn_safe(settings) then
        pcall(printf, "[ct:294] SKIP non-resident pickup '%s' (unit=%s not loaded) -- would crash spawn_network_unit/add_unit_extensions",
            tostring(pickup_name), tostring(settings and settings.unit_name))
        return
    end

    -- #58/#156 spawn census: count the FINAL pickup_name (post collectible->coin
    -- conversion) once vanilla confirms it actually spawned. _spawn_pickup is the
    -- single chokepoint for both the spread pass and the guaranteed chest/altar pass,
    -- so this tallies EVERYTHING. #322: vanilla returns (pickup_unit, pickup_unit_go_id)
    -- (pickup_system.lua:1207); capture and re-return BOTH. Only one vanilla caller uses
    -- the go_id -- the linked-pickup RPC path (:1441 -> rpc_link_pickup) -- so dropping it
    -- (the old `return spawned`, VMF_RECIPES 2 collapse) desynced surface-linked pickups
    -- to clients. The #294 guard's early `return` (nil,nil) matches vanilla's own early
    -- returns, so it stays correct.
    local spawned, go_id = func(self, settings, pickup_name, position, rotation, flag, spawn_type, ...)
    if mod._ct_tally_count then mod._ct_tally_count(pickup_name, spawned) end
    -- #143 (read-only): tag every CONFIRMED Morgrim's Bomb spawn with its source
    -- (world spread-pool vs level-baked vs bomb-boon drop) so a live run settles
    -- whether the over-appearance origin is the world weight or the boon re-drop.
    if pickup_name == "holy_hand_grenade" and spawned ~= nil and mod._ct_morgrim143_count then
        mod._ct_morgrim143_count(spawn_type, on_adv)
    end
    -- #143 round 2: per-session tally of EVERY grenade-type spawn so holy's share is
    -- computable from any log (world-spawn side is proven fixed; this keeps the receipt).
    if spawned ~= nil and mod._ct_morgrim143_grenade_tally then
        mod._ct_morgrim143_grenade_tally(pickup_name)
    end
    return spawned, go_id
end)
-- issue 511: load-time provenance marker for the #322 two-return _spawn_pickup hook
-- above. The VMF Lua sandbox exposes NO `io`, so the old source self-grep threw
-- "attempt to index global 'io'" and FAILED /ct_regression_test on healthy code;
-- the check now asserts this marker (set beside the hook at load) instead. The
-- exact 2-value capture/return SHAPE is a source invariant flagged for a repo QA
-- gate (PROJECT_STANDARDS 2.2b tier a).
CT_SPAWN_PICKUP322_MARKER = "spawn_pickup322:two_value_capture_and_return_v0.7.245"

-- Loot dice rolled from an opened chest do not call PickupSystem at all:
-- InteractionDefinitions.chest.server.stop builds pickup init data and calls
-- UnitSpawner.spawn_network_unit directly [src: interactions.lua:2112-2138].
-- Rewrite that exact pickup identity at the authoritative owner-spawn seam;
-- UnitSpawner then serializes the coin identity into the game object and clients
-- create only the replicated coin husk [src: unit_spawner.lua:336-352,470-490].
-- Stock Adventure, clients, and every non-collectible network unit pass through.
mod:hook("UnitSpawner", "spawn_network_unit", function(func, self, unit_name,
        unit_template_name, extension_init_data, position, rotation, material, ...)
    local pickup_data = type(extension_init_data) == "table" and extension_init_data.pickup_system
    local candidate = type(pickup_data) == "table"
        and _CW_COLLECTIBLE_TO_COIN[pickup_data.pickup_name]
    if candidate then
        local coin_settings = AllPickups and AllPickups.deus_soft_currency
        local rewritten_unit, rewritten_template, rewritten_init, converted, original_name =
            mod._ct_collectible_policy.rewrite_network_spawn(unit_name, unit_template_name,
                extension_init_data, coin_settings, on_injected_adventure_level(),
                self.is_server == true)
        if converted then
            mod._ct351_log_conversion("unit_spawner", original_name)
            return func(self, rewritten_unit, rewritten_template, rewritten_init,
                position, rotation, material, ...)
        end
    end
    return func(self, unit_name, unit_template_name, extension_init_data,
        position, rotation, material, ...)
end)
-- Note: previous versions attempted to make altars/chests walk-through by mutating
-- their actor collision filter / scene_query / collision_enabled flags. This
-- ALWAYS regressed interaction (v0.6.28 scene_query disable broke chest open;
-- v0.6.32 filter_trigger broke it again). The Peregrinaje mod ships chests without
-- a physics blocker by some other mechanism — investigate that pattern before
-- re-attempting any collision-disable here.

mod:hook("PickupSystem", "_spawn_guaranteed_pickup", function(func, self, spawner_unit, spawn_type)
    if not on_injected_adventure_level() then
        return func(self, spawner_unit, spawn_type)
    end

    -- loot_die spawners on Bogenhafen (Brugrodder '68 bottle, etc.) are guaranteed
    -- side-objective collectibles. We have no CW equivalent system — convert these
    -- positions to deus_soft_currency (Pilgrim's Coin) so the spawner still gives
    -- something useful instead of dropping a collectible the run can't interact with.
    if Unit.get_data(spawner_unit, "loot_die") or Unit.get_data(spawner_unit, "lorebook_page") then
        local settings = AllPickups and AllPickups.deus_soft_currency
        if settings then
            local position = Unit.local_position(spawner_unit, 0)
            local rotation = Unit.local_rotation(spawner_unit, 0)
            return self:_spawn_pickup(settings, "deus_soft_currency", position, rotation, false, spawn_type)
        end
        return func(self, spawner_unit, spawn_type)
    end

    -- v0.7.65: sentinel -1 → 1 (vanilla default); 0+ → use as-is.
    -- Hoisted ABOVE the tome/grim early-out (was below it) so the native
    -- deus_cursed_chest branch added right below can reuse the same cap. Vanilla
    -- adventure maps ship 5 book pedestals (3 tomes + 2 grimoires), so up to 4
    -- spots remain afterwards.
    local cap_raw = effective_setting("cursed_chest_count") or -1  -- v0.7.42: sync with host
    local cap = (cap_raw == -1) and 1 or cap_raw

    -- v0.7.157-dev (Issue #60): native level-baked `deus_cursed_chest` spawners.
    -- ----------------------------------------------------------------------------
    -- Most injected adventure maps (dlc_termite_1, dlc_bastion, etc.) carry ONLY
    -- tome/grimoire pedestals, so every Chest of Trials they show is produced by
    -- the tome/grim → chest CONVERSION below — already capped by
    -- `mod._ct_chest_conversions_this_level < cap`. Those maps spawn exactly `cap` chests
    -- and need no change here.
    --
    -- dlc_dwarf_beacons ("Khazukan Kazakit-ha!") is the outlier: its LEVEL GEOMETRY
    -- ships its own guaranteed spawners natively flagged `deus_cursed_chest` (NOT
    -- tome/grim), IN ADDITION TO book pedestals. Vanilla `_spawn_guaranteed_pickup`
    -- spawns those baked chests unconditionally — they are not drawn from the
    -- pickup sampler, so the `populate_pickups` sampler-count cap never touches them,
    -- and before this fix they ALSO failed the is_tome/is_grim test below and fell
    -- straight through to vanilla. Result: cap=3 produced 3 converted chests + 2
    -- baked chests = 5 total (the #60 report).
    --
    -- Fix: route native `deus_cursed_chest` spawners through the SAME per-mission
    -- `mod._ct_chest_conversions_this_level < cap` budget the conversion path uses. Under
    -- the cap, let vanilla spawn the baked chest (and count it against the budget);
    -- AT/OVER the cap, suppress the spawner (return nothing → empty pedestal, same
    -- as the cap-reached tome/grim fallthrough). Host-authoritative:
    -- `_spawn_guaranteed_pickup` runs on the server for injected levels, so the
    -- decision is made once by the host and is not a per-peer divergence.
    --
    -- This is surgical — it ONLY fires for spawners the level natively tags
    -- `deus_cursed_chest`. Maps with no such baked spawners (termite/bastion/vanilla
    -- CW paths) never enter this branch and keep spawning exactly `cap` chests.
    if Unit.get_data(spawner_unit, "deus_cursed_chest") then
        if mod._ct_chest_conversions_this_level < cap then
            -- Count the baked chest against the same budget the conversions use,
            -- then let vanilla spawn it from its native flag.
            mod._ct_chest_conversions_this_level = mod._ct_chest_conversions_this_level + 1
            -- [ct-probe] unconditional: native baked cursed-chest ALLOWED under cap.
            -- Survives a VMF-mod-logging-OFF host (raw print, not mod:info). #60.
            local pok = pcall(function()
                local cur = LevelHelper and LevelHelper:current_level_settings()
                printf("[ct-probe] baked_cursed_chest=ALLOW level=%s cap=%d count_now=%d",
                    tostring(cur and cur.level_id), cap, mod._ct_chest_conversions_this_level)
            end)
            if not pok then printf("[ct-probe] baked_cursed_chest=ALLOW (level-id read failed) cap=%d count_now=%d", cap, mod._ct_chest_conversions_this_level) end
            _dbg("[baked_chest] -> ALLOW (vanilla spawn) cap=%d count_now=%d", cap, mod._ct_chest_conversions_this_level)
            return func(self, spawner_unit, spawn_type)
        end
        -- Budget exhausted: suppress this baked spawner so the level total never
        -- exceeds `cap`. Returning nothing skips the spawn; the pedestal stays
        -- empty (adventure flow units only materialize on spawn).
        -- [ct-probe] unconditional: native baked cursed-chest SUPPRESSED over cap.
        local pok2 = pcall(function()
            local cur = LevelHelper and LevelHelper:current_level_settings()
            printf("[ct-probe] baked_cursed_chest=SUPPRESS level=%s cap=%d count=%d (over budget)",
                tostring(cur and cur.level_id), cap, mod._ct_chest_conversions_this_level)
        end)
        if not pok2 then printf("[ct-probe] baked_cursed_chest=SUPPRESS (level-id read failed) cap=%d count=%d", cap, mod._ct_chest_conversions_this_level) end
        _dbg("[baked_chest] -> SUPPRESS (over cap) cap=%d count=%d", cap, mod._ct_chest_conversions_this_level)
        return
    end

    local is_tome = Unit.get_data(spawner_unit, "tome")
    local is_grim = Unit.get_data(spawner_unit, "grimoire")
    if not is_tome and not is_grim then
        return func(self, spawner_unit, spawn_type)
    end

    -- Respect the user's `cursed_chest_count` setting. The first N book spots become
    -- Chests of Trials. Default ("Default" sentinel = -1) treats this as the vanilla
    -- value of 1 chest per mission; explicit 0 leaves all book spots empty.
    -- v0.7.125-dev (Issue #60): trace every conversion attempt so we can diagnose
    -- "5 chests spawned with host cap=3" reports. Logs cap_raw + cap + the running
    -- counter at decision time. Cheap; fires at most 5 times per mission load.
    _dbg("[pedestal] kind=%s cap_raw=%s cap=%d count=%d", is_tome and "tome" or "grim",
        tostring(cap_raw), cap, mod._ct_chest_conversions_this_level)
    if mod._ct_chest_conversions_this_level < cap then
        local pickup_name = "deus_cursed_chest"
        local settings = AllPickups and AllPickups[pickup_name]
        if not settings then
            -- AllPickups not yet built (extremely unlikely at populate time, but defensive).
            return func(self, spawner_unit, spawn_type)
        end

        local position = Unit.local_position(spawner_unit, 0)
        local rotation = Unit.local_rotation(spawner_unit, 0)
        local spawned_unit = self:_spawn_pickup(settings, pickup_name, position, rotation, false, spawn_type)
        mod._ct_chest_conversions_this_level = mod._ct_chest_conversions_this_level + 1
        -- [ct-probe] unconditional: tome/grim pedestal CONVERTED to a cursed chest
        -- under cap. This is the path termite/bastion/vanilla CW maps use (no baked
        -- deus_cursed_chest spawners), so without this line a logging-OFF host could
        -- count ACTUAL chests only on the Beacons (baked-spawner) path. Pairs with the
        -- baked_cursed_chest=ALLOW probe above to give the true per-map total. Raw
        -- printf bypasses the VMF mod-logging toggle (lands on Rain's logging-OFF host). #60.
        local pokc = pcall(function()
            local cur = LevelHelper and LevelHelper:current_level_settings()
            printf("[ct-probe] conversion_cursed_chest=ALLOW kind=%s level=%s cap=%d count_now=%d spawned=%s",
                is_tome and "tome" or "grim", tostring(cur and cur.level_id), cap,
                mod._ct_chest_conversions_this_level, tostring(spawned_unit ~= nil))
        end)
        if not pokc then printf("[ct-probe] conversion_cursed_chest=ALLOW (level-id read failed) cap=%d count_now=%d", cap, mod._ct_chest_conversions_this_level) end
        _dbg("[pedestal] -> chest_of_trials count_now=%d (spawned=%s)", mod._ct_chest_conversions_this_level,
            tostring(spawned_unit ~= nil))
        return spawned_unit
    end

    -- v0.7.55: after Chests of Trials are placed, the NEXT remaining book spot becomes
    -- the Belakor altar (`deus_02` / `deus_belakor_locus`) when the host has "Always
    -- Include Belakor's Temple" on. One altar per mission, matching vanilla
    -- belakor-themed CW levels which all request `deus_02 = 1`. The `_spawn_pickup`
    -- call below also re-checks `can_spawn_belakor_locus` (vanilla pickup-settings
    -- `can_spawn_func` gate), which our DeusRunController.can_spawn_belakor_locus hook
    -- below permits on adventure-injected levels — both paths must agree, or the call
    -- silently no-ops.
    -- v0.7.64: locus only spawns on the actual Belakor cursed mission. Previously
    -- `force_belakor` alone caused the locus to land on the FIRST adventure-injected
    -- book pedestal regardless of which node held curse_belakor_totems — so in last
    -- night's run the locus landed on nurgle_slaanesh_path1 while the actual Belakor
    -- mission (magnus_belakor_path1) got nothing. `_current_node_is_belakor()` reads
    -- the current node's curse field, which is the only data that identifies "this
    -- mission has the Belakor totems curse." `force_belakor` itself only guarantees a
    -- Belakor curse appears SOMEWHERE in the run — it doesn't say where.
    -- v0.7.125-dev (Issue #60): log every altar-spawn decision so we can
    -- diagnose "no shadow locus on Belakor mission" reports. Captures every gate
    -- (force_belakor, current_node_is_belakor, AllPickups.deus_02, already-spawned).
    local altar_should = (not mod._ct_belakor_altar_spawned_this_level)
        and effective_setting("force_belakor")
        and _current_node_is_belakor()
        and (AllPickups and AllPickups.deus_02 ~= nil)
    _dbg("[pedestal] altar_gate force_belakor=%s current_is_belakor=%s have_deus_02=%s already_spawned=%s -> attempt=%s",
        tostring(effective_setting("force_belakor")),
        tostring(_current_node_is_belakor()),
        tostring(AllPickups and AllPickups.deus_02 ~= nil),
        tostring(mod._ct_belakor_altar_spawned_this_level),
        tostring(altar_should))
    if altar_should then
        local position = Unit.local_position(spawner_unit, 0)
        local rotation = Unit.local_rotation(spawner_unit, 0)
        local spawned_unit = self:_spawn_pickup(AllPickups.deus_02, "deus_02", position, rotation, false, spawn_type)
        _dbg("[pedestal] -> belakor_altar spawn=%s (vetoed=%s)", tostring(spawned_unit ~= nil),
            tostring(spawned_unit == nil))
        if spawned_unit then
            mod._ct_belakor_altar_spawned_this_level = true
            return spawned_unit
        end
        -- _spawn_pickup returns nil if can_spawn_func vetoed; fall through to "skip
        -- this spawner" so the empty pedestal stays hidden, same as the no-cap case.
    end

    -- v0.7.148: leftover book pedestals (a tome/grimoire spot NOT taken by a Chest
    -- of Trials or the Belakor locus) become a BIGGER coin casket instead of an
    -- empty spot -- a reward where the book would have been. The casket is the
    -- normal deus_soft_currency pickup (deus_loot_pyramide_01) scaled to 1.75x and
    -- tagged `ct_big_casket`; the _get_coins_amount_and_type hook below grants it
    -- 3x the coin a normal casket would. _spawn_guaranteed_pickup runs per-peer on
    -- injected levels, so the scale + tag land on every peer's copy.
    do
        local casket_settings = AllPickups and AllPickups.deus_soft_currency
        if casket_settings then
            local position = Unit.local_position(spawner_unit, 0)
            local rotation = Unit.local_rotation(spawner_unit, 0)
            local casket = self:_spawn_pickup(casket_settings, "deus_soft_currency", position, rotation, false, spawn_type)
            -- [ct:456] leftover book spot (this pedestal was NOT the chest): report the
            -- casket outcome + position unconditionally. A grimoire that lands here with
            -- spawned=false is the "always empty" symptom on the guaranteed path (case c);
            -- spawned=true means the spot got a casket, so the "empty" report is elsewhere.
            pcall(function()
                local p = Unit.local_position(spawner_unit, 0)
                printf("[ct:456] leftover_book kind=%s casket_spawned=%s pos=(%.1f,%.1f,%.1f)",
                    is_tome and "tome" or "grim", tostring(casket and Unit.alive(casket) and true or false),
                    Vector3.x(p), Vector3.y(p), Vector3.z(p))
            end)
            if casket and Unit.alive(casket) then
                Unit.set_data(casket, "ct_big_casket", true)
                Unit.set_local_scale(casket, 0, Vector3(1.75, 1.75, 1.75))
                _dbg("[pedestal] -> BIG coin casket (1.75x scale, 3x coin) at leftover book spot")
                return casket
            end
        end
    end

    -- Could not build the casket (settings missing) — leave the spawner alone
    -- (empty pedestal stays hidden because adventure flow units only materialize
    -- after spawn).
    -- [ct:456] unconditional: this book pedestal produced NOTHING (empty). Pinpoints the
    -- "location of the first Grimoire is always empty" symptom on the guaranteed path.
    pcall(function()
        local p = Unit.local_position(spawner_unit, 0)
        printf("[ct:456] empty_book kind=%s pos=(%.1f,%.1f,%.1f) (cap reached, altar n/a, casket settings missing)",
            is_tome and "tome" or "grim", Vector3.x(p), Vector3.y(p), Vector3.z(p))
    end)
    _dbg("[pedestal] -> empty (cap reached, altar n/a, casket settings missing)")
    return
end)

-- Big coin casket payout: the leftover-book-spot casket (tagged ct_big_casket
-- above) grants 3x the coin a normal deus_soft_currency casket would. We wrap the
-- per-pickup amount roll rather than on_soft_currency_picked_up so only THIS
-- pickup is tripled (not enemy/ground coin). No existing ct hook on this method.
mod:hook("GameModeDeus", "_get_coins_amount_and_type", function(func, self, interactable_unit)
    local amount, ctype = func(self, interactable_unit)
    if type(amount) == "number" and interactable_unit and Unit.alive(interactable_unit)
        and Unit.get_data(interactable_unit, "ct_big_casket") then
        return amount * 3, ctype
    end
    return amount, ctype
end)
