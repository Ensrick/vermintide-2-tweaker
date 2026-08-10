--[[
_ct_pickup_population_owner - the per-mission pickup POPULATION pass, and the
census that proves what came out of it (#1159 / #2 file-size refactor).

RESPONSIBILITY
Owns everything ct does at `PickupSystem.populate_pickups` - the single host-side
call that runs once per mission load, before any pickup unit exists - together
with the ledger that counts what that pass actually produced. Concretely:
  * the BUDGET. `LevelSettings[level].pickup_settings` is patched in place for the
    duration of vanilla's call so the mission spawns the configured number of
    altars (`deus_weapon_chest`), Chests of Trials (`deus_cursed_chest`) and arena
    ammo crates (`ammo`). Every touched field is saved before and restored after,
    arena levels are detected by the ABSENCE of a `deus_weapon_chest` key and take
    the ammo path instead, and the -1 sentinel means "Default, do not override" as
    distinct from an explicit 0.
  * the POOLS that pass samples from. The three campaign potions are cloned into
    `Pickups.deus_potions` and the WHOLE group is renormalized to sum 1.0, because
    vanilla's `_spawn_spread_pickups` sampler breaks on the first cumulative >=
    random roll and anything past cumulative 1.0 is simply unreachable. The #143
    Morgrim's Bomb over-spawn fix halves `holy_hand_grenade` and redistributes the
    freed half to the other grenades PROPORTIONALLY, so the pool SUM is unchanged
    - that sum-preservation is what makes it provably immune to the v0.7.143
    sampler crash. Both mutations are restored after vanilla returns.
  * the CENSUS (#58 / #156). The `mod._ct_tally_*` ledger - reset / count / tick /
    cursed_count - tallies every pickup by final `pickup_name` and emits ONE raw
    `printf` summary ~8s later, by which point the guaranteed-spawn pass has run.
    Raw printf bypasses every VMF logging toggle, so `total=0` on an injected level
    lands as an unambiguous "this map is broken" signal on a logging-OFF host with
    no dump command and no debug toggle.
  * the ENTRY PROBES that make a broken mission diagnosable from the log alone: the
    `[ct-probe]` cursed-chest cap line, the `[populate_pickups]` line (level,
    mechanism, difficulty, `has_pickup_settings`, injection gate, spawner-list
    counts) and the `[ct:456]` book-spawner census dispatch.
  * the #132 spawn-path-independent chest ground truth,
    `DeusCursedChestExtension.extensions_ready`, which fires for every cursed chest
    that exists regardless of HOW it spawned - so it catches chests that bypass the
    pickup system, and thus the cap, entirely. Read-only here; cap and census are
    resolved and handed to `_ct_diag_cursed_chest132.lua`, which owns the counter.
  * the two per-level counters the guaranteed-spawn pass consumes,
    `mod._ct_chest_conversions_this_level` and
    `mod._ct_belakor_altar_spawned_this_level`. They are RESET here because
    populate_pickups is the one per-mission "run boot" seam on the host, and both
    resets were deliberately consolidated into this single hook to avoid VMF's
    "Attempting to rehook active hook" warning.

Extracted from chaos_wastes_tweaker_dev.lua entry lines 3566-4065. ONE contiguous
chunk moved; every line inside it is byte-identical to the pre-extraction entry
region except the TWO documented lines under DEVIATIONS below (MD5-proven over the
region with those two lines excluded). The only additions are this header, the ctx
binding block, and the closing `end` / `return install`. mod:dofile is not a
singleton, so the entry calls this installer EXACTLY once.

ZERO LOAD-ORDER DEVIATION
The installer sits at the exact line the moved region occupied - immediately after
the `DeusMechanism.game_round_ended` hook and immediately before the Holy Hand
Grenade spawn-rate section - so every hook in the mod still registers in its
original relative order. Nothing was reordered, split, or skipped.

HOOKS OWNED (each hooked EXACTLY ONCE in the whole mod - VMF silently drops a
second registration on the same (Class, method) pair)
  DeusCursedChestExtension.extensions_ready   [hook_safe]
  PickupSystem.populate_pickups               [hook]
No RPC, no command, no `_rt_register` moved with this slice. The mod-wide hook
census is unchanged by the move, verified before and after by two independent
methods against a pristine `git archive` checkout.

CROSS-FILE CONTRACT
Entry file-locals the moved chunk closed over, and how each crosses. The three
READ crossings bind to the SAME NAME the chunk already used, which is what lets
those lines stay byte-identical:
  ctx.effective_setting              entry :785, assigned at :2054. Crosses as a
      -> local effective_setting     late-binding wrapper, not by value: the entry
                                     assigns the forward-declared slot ABOVE this
                                     install site today, so by-value would also be
                                     correct today, but the wrapper survives the
                                     install site moving. Same treatment as
                                     _ct_altar_reuse_owner (#1236) and
                                     _ct_boon_offer_view_owner (#1240).
  ctx.dump_pickup_system_state       entry :803 / :804. These two are FORWARD
  ctx.dump_pickup_spawners_verbose   DECLARATIONS whose `function _name(...)` bodies
      -> local _dump_pickup_*        are assigned at entry :4658 / :4781, which is
                                     BELOW this install site. A by-value bind here
                                     would freeze nil and both post-populate dumps
                                     would silently no-op forever. The wrapper reads
                                     the entry's local at CALL time - populate_pickups
                                     first fires at mission load, long after the entry
                                     chunk finished - so both dumps still fire. This is
                                     the crossing that sank three earlier attempts at
                                     this cluster; `install_late_bound_dumps_survive`
                                     in the test suite pins it by asserting a wrapper
                                     whose target is assigned only AFTER install.
  ctx.set_career_exclusive_denial_counts     entry :687 / :690. These are the only
  ctx.set_career_exclusive_logged_this_run   WRITE crossings: the chunk REASSIGNS both
                                     entry locals to fresh tables. A module cannot
                                     assign another chunk's local, so they cross as
                                     setters - see DEVIATIONS.
`mod` is the installer's first parameter, exactly as the other ct owners take it.
`_CAMPAIGN_POTION_NAMES` - the only main-chunk local the moved region DECLARED -
had zero references anywhere outside those lines, so it becomes an install-scope
local with identical closure semantics and crosses nothing. Everything else the
chunk reads is either an engine global reachable from any chunk (Pickups,
LevelHelper, Managers, printf, table, unpack, type, pairs, ipairs, tostring,
pcall) or a `mod._ct_*` field resolved off `mod` at CALL time and therefore
already immune to chunk boundaries: `mod._ct_chest132`, `mod._ct_effective_setting`,
`mod._ct_on_injected_adventure_level`, `mod._ct_adventure_base_from_level_key`,
`mod._ct_book_spawner_census`, `mod._ct_rebuild_coin_reserved_set`,
`mod._ct_clear_coin_reserved_set`.

DEVIATIONS (exactly two lines; both exist to preserve behaviour across the chunk
boundary, and both are pinned by executable tests)
The reset at the top of populate_pickups was:
        _career_exclusive_denial_counts = {}
        _career_exclusive_logged_this_run = {}
and is now:
        _set_career_exclusive_denial_counts({})
        _set_career_exclusive_logged_this_run({})
Assignment, not mutation, is the behaviour that has to survive: the entry hands
`_ct_spawn_eligibility_owner` GETTER closures (entry :5385 / :5386) that resolve
those locals at call time precisely because this hook rebinds them, and the
`verify_engineer_bombs` command reads the entry local directly. A setter passed
through ctx reassigns the entry's local exactly as the original line did, so every
reader still observes a FRESH table per mission. `table.clear` in place was
rejected: it would leave table identity unchanged, which is a real semantic
difference for any future holder of a direct reference, and it would make the
"fresh table per populate" contract untestable. One line in, one line out, same
order, same values.

COMPOSES WITH, DOES NOT OVERLAP, THE OTHER ct PICKUP OWNERS
Three owners now sit on PickupSystem, each on its own (Class, method) pair, which
is what keeps them collision-free:
  * this file owns `populate_pickups` - the per-mission BUDGET and the census.
    How MANY of each thing the mission is allowed to make, which pools are
    reachable while it makes them, and the ledger of what appeared.
  * `_ct_pickup_spawn_owner` owns `_spawn_pickup` and `_spawn_guaranteed_pickup` -
    WHAT unit materializes at one spawn seam and what it pays out. It is the
    WRITER of `mod._ct_chest_conversions_this_level` /
    `mod._ct_belakor_altar_spawned_this_level` (this file is the resetter) and the
    caller of `mod._ct_tally_count` (this file owns the ledger). Both seams are
    `mod` fields resolved at call time and are unchanged by this move.
  * `_ct_spawn_eligibility_owner` owns `_can_spawn` - WHETHER a candidate may
    spawn at all. It consumes the coin-reservation set this file rebuilds once per
    pass, and the career-exclusive counters this file resets once per pass, both
    through call-time accessors.
  * `_ct_diag_cursed_chest132` owns the per-mission cursed-chest reconcile ledger;
    this file only feeds it (`begin`, `pickup_chest`, `chest_appeared`,
    `finalize`). It must never grow its own counter.
  * `_adventure_pool` decides WHICH levels are injected; this file only asks, via
    `mod._ct_on_injected_adventure_level`, and must keep working whatever the
    answer is.
Nothing here may read a boon, a price, or a curse: the pickup population pass is
independent of the boon economy and stays that way.

EXPORTS: none by return value. The seams this owner publishes are the `mod` fields
the moved code already assigned - `mod._ct_tally_reset`, `mod._ct_tally_count`,
`mod._ct_tally_tick`, `mod._ct_tally_cursed_count`, `mod._CT_SPAWN_TALLY_MARKER`,
`mod._ct_chest_conversions_this_level`, `mod._ct_belakor_altar_spawned_this_level`
- because their consumers (the entry's `mod.update` drainer,
`_ct_pickup_spawn_owner`, `_ct_regression`) all resolve them off `mod` at CALL
time. An install-time return would be a second, divergent channel for state that
is already reachable, so the shape stays exactly as it was pre-extraction.

Owned by: chaos_wastes_tweaker_dev.lua entry point.
Guarded by: qa/lua/tests/test_ct_pickup_population_owner.lua,
qa/lua/tests/test_ct_entry_decomposition.lua, the census / forward-declaration
checks in _ct_regression.lua, and the PickupSystem +
DeusCursedChestExtension.extensions_ready rows in
chaos_wastes_tweaker_dev/ENGINE_SURFACE.md.
]]

local function install(mod, ctx)

assert(type(ctx) == "table", "_ct_pickup_population_owner requires a context table")
assert(type(ctx.effective_setting) == "function",
    "_ct_pickup_population_owner requires ctx.effective_setting (late-binding wrapper)")
assert(type(ctx.dump_pickup_system_state) == "function",
    "_ct_pickup_population_owner requires ctx.dump_pickup_system_state (late-binding wrapper: the entry assigns that forward-declared slot BELOW this install site)")
assert(type(ctx.dump_pickup_spawners_verbose) == "function",
    "_ct_pickup_population_owner requires ctx.dump_pickup_spawners_verbose (late-binding wrapper: the entry assigns that forward-declared slot BELOW this install site)")
assert(type(ctx.set_career_exclusive_denial_counts) == "function",
    "_ct_pickup_population_owner requires ctx.set_career_exclusive_denial_counts (setter: the reset REASSIGNS the entry local)")
assert(type(ctx.set_career_exclusive_logged_this_run) == "function",
    "_ct_pickup_population_owner requires ctx.set_career_exclusive_logged_this_run (setter: the reset REASSIGNS the entry local)")

-- The moved chunk below calls `effective_setting(...)`, `_dump_pickup_system_state`
-- and `_dump_pickup_spawners_verbose` unqualified, exactly as it did in the entry.
-- Binding the ctx wrappers to those same names is what lets those lines stay
-- byte-identical across the move.
local effective_setting = ctx.effective_setting
local _dump_pickup_system_state = ctx.dump_pickup_system_state
local _dump_pickup_spawners_verbose = ctx.dump_pickup_spawners_verbose
-- The two WRITE crossings. See DEVIATIONS in the header: a chunk cannot assign
-- another chunk's local, so the per-mission reset goes through these setters and
-- the entry local is rebound to a fresh table exactly as before.
local _set_career_exclusive_denial_counts = ctx.set_career_exclusive_denial_counts
local _set_career_exclusive_logged_this_run = ctx.set_career_exclusive_logged_this_run

-- ============================================================
-- Spawn census (Issue #58 / #156) — UNCONDITIONAL pickup count per mission
-- ============================================================
-- The recurring "Horn of Magnus / injected adventure map spawns NOTHING" bug
-- (no chests, no altars, no pickups; intermittent) was historically un-diagnosable
-- because the only log evidence was `has_pickup_settings` + the *configured*
-- cursed_chest_count -- never what ACTUALLY spawned. This census counts every
-- pickup that passes through PickupSystem._spawn_pickup -- the SINGLE chokepoint
-- for BOTH the spread pass (ammo/healing/potions/coins) and the guaranteed pass
-- (Chests of Trials, Belakor altar, caskets) -- keyed by final pickup_name, and
-- emits ONE `printf` summary ~8s after the host's populate_pickups (by which point
-- the guaranteed-spawn pass has fully run). Raw printf bypasses every VMF/mod
-- logging toggle, so it lands on a logging-OFF host with NO dump command and NO
-- debug toggle. `total=0` on an injected level is the unambiguous "this map is
-- broken" signal; the injected=/adv_base=/diff= fields on this line + the
-- [populate_pickups] line say WHY in the same breath. (The aggregate avoids the
-- per-spawner printf flood that would tank FPS -- see #104.)
do
    local _counts = {}
    local _total = 0
    local _level, _injected, _adv_base, _difficulty = nil, nil, nil, nil
    local _armed = false
    local _elapsed = 0
    local _EMIT_DELAY = 8.0  -- seconds; guaranteed-spawn pass completes well within this window

    mod._ct_tally_reset = function(level_key, injected, adv_base, difficulty)
        table.clear(_counts)
        _total = 0
        _level, _injected, _adv_base, _difficulty = level_key, injected, adv_base, difficulty
        _armed = true
        _elapsed = 0
        if mod._ct_chest132 and mod._ct_chest132.begin then
            mod._ct_chest132.begin(level_key)
        end
    end

    mod._ct_tally_count = function(pickup_name, spawned_unit)
        if not _armed or spawned_unit == nil then return end
        local k = tostring(pickup_name)
        _counts[k] = (_counts[k] or 0) + 1
        _total = _total + 1
        -- v0.7.298-dev (issue 132): pickup-path chest units are engine-deletable; ledger them for the settled reconcile.
        if k == "deus_cursed_chest" and mod._ct_chest132 and mod._ct_chest132.pickup_chest then pcall(mod._ct_chest132.pickup_chest, spawned_unit) end
    end

    local function _emit()
        local ok = pcall(function()
            local cursed  = _counts.deus_cursed_chest or 0
            local weapon  = _counts.deus_weapon_chest or 0
            local altar   = _counts.deus_02 or 0
            local coins   = _counts.deus_soft_currency or 0
            local potions = 0
            for name, n in pairs(_counts) do
                if Pickups and Pickups.deus_potions and Pickups.deus_potions[name] then potions = potions + n end
            end
            local keys = {}
            for k in pairs(_counts) do keys[#keys + 1] = k end
            table.sort(keys)
            local parts = {}
            for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. tostring(_counts[k]) end
            printf("[ct-spawn-tally] level=%s injected=%s adv_base=%s diff=%s total=%d ZERO=%s | chests(cursed=%d weapon=%d) altar=%d coins=%d potions=%d | %s",
                tostring(_level), tostring(_injected), tostring(_adv_base), tostring(_difficulty),
                _total, tostring(_total == 0), cursed, weapon, altar, coins, potions,
                table.concat(parts, " "))
            -- #349: classify the extension-level ground truth only after this
            -- delayed pickup census has settled. extensions_ready itself fires
            -- synchronously before _spawn_pickup returns, so comparing there is
            -- inherently one chest early and cannot prove a bypass.
            if mod._ct_chest132 and mod._ct_chest132.finalize then
                local cap = mod._ct_effective_setting and mod._ct_effective_setting("cursed_chest_count")
                cap = (cap == -1 or cap == nil) and 1 or cap
                local is_server = Managers and Managers.player and Managers.player.is_server and true or false
                mod._ct_chest132.finalize(_level, cap, cursed, is_server)
            end
        end)
        if not ok then pcall(printf, "[ct-spawn-tally] level=%s emit failed (total=%d)", tostring(_level), _total) end
    end

    mod._ct_tally_tick = function(dt)
        if not _armed then return end
        _elapsed = _elapsed + (dt or 0)
        if _elapsed >= _EMIT_DELAY then
            _armed = false
            _emit()
        end
    end
    -- #132 cross-check accessor: the running count of deus_cursed_chest (Chest of
    -- Trials) spawns the census has seen at PickupSystem._spawn_pickup so far this
    -- mission. The [ct:132] extensions_ready probe compares its spawn-path-
    -- independent ground truth against this: ground_truth > census means chests
    -- exist that never routed through the pickup system (raw baked level units).
    mod._ct_tally_cursed_count = function()
        return _counts.deus_cursed_chest or 0
    end
    -- Regression marker (PROJECT_STANDARDS.md hook-consolidation doctrine): census is
    -- wired through the SINGLE existing _spawn_pickup hook + the existing mod.update
    -- drainer; no new hook on PickupSystem._spawn_pickup / no second mod.update owner.
    mod._CT_SPAWN_TALLY_MARKER = "CT_SPAWN_TALLY_v1_unconditional_census"
end

-- #132 DIAGNOSTIC: spawn-path-independent Chest-of-Trials ground truth.
-- DeusCursedChestExtension.extensions_ready (deus_cursed_chest_extension.lua:39)
-- fires once per cursed chest that actually exists in the world, on every peer,
-- regardless of HOW the chest spawned - so it catches chests that bypass the
-- pickup system (and thus the cursed_chest_count cap) entirely. Distinct method
-- from the existing _set_state hook, so this fresh hook is VMF-clean. Read-only;
-- cap/census are resolved here and handed to the #132 module which owns the
-- per-mission counter + emit. See _ct_diag_cursed_chest132.lua for the full why.
mod:hook_safe("DeusCursedChestExtension", "extensions_ready", function(self, world, unit)
    if not mod._ct_chest132 then return end
    pcall(function()
        local cur = LevelHelper and LevelHelper:current_level_settings()
        local level_id = (cur and cur.level_id) or "?"
        local cap = mod._ct_effective_setting and mod._ct_effective_setting("cursed_chest_count")
        cap = (cap == -1 or cap == nil) and 1 or cap
        local census = mod._ct_tally_cursed_count and mod._ct_tally_cursed_count() or -1
        local is_server = (Managers and Managers.player and Managers.player.is_server) and true or false
        -- v0.7.298-dev (issue 132 / issue 60): unit feeds the reconcile ledger.
        mod._ct_chest132.chest_appeared(level_id, cap, census, is_server, unit)
    end)
end)

-- CLARIFY: Patches LevelSettings[level].pickup_settings to control the COUNT of altars/cursed
-- chests/arena ammo crates spawned per mission. This works alongside `get_deus_weapon_chest_type`
-- which controls the TYPE distribution within each chest. Net effect:
--   - altar_total > 0: spawn this many altars total (types determined by chest_*_count proportions)
--   - cursed_count != 1: override cursed-chest count (vanilla = 1)
--   - arena_ammo != 2: override arena ammo box count (vanilla = 2)
--   - potions_on: inject campaign damage/speed/CDR potions into Pickups.deus_potions for this mission
-- All settings save/restore around `func()` so vanilla values are preserved between runs.
-- POTENTIAL BUG (LOW): Same `func` error → state leak issue as boon/trait hooks. If `func()` raises,
-- pickup_settings stays mutated AND added_potions clones leak in Pickups.deus_potions.
--
-- Per-level counter for tome/grim → Chest of Trials conversions. A `mod` field, not
-- a file-local: the only WRITER of the increments is the _spawn_guaranteed_pickup
-- hook, which now lives in _ct_pickup_spawn_owner.lua (#1159), and a separate chunk
-- cannot bind this file's locals. It was a local purely so that lexically-earlier
-- hook could see it at closure-creation time (feedback_lua_forward_reference.md);
-- crossing a chunk boundary needs the `mod` escape hatch instead (same reason as
-- mod._ct_pending_team_teleport). Reset stays here, at the top of THIS hook
-- (consolidated to avoid the VMF "Attempting to rehook active hook" warning for
-- populate_pickups) — reset timing and value are unchanged by the move.
local _CAMPAIGN_POTION_NAMES = { "damage_boost_potion", "speed_boost_potion", "cooldown_reduction_potion" }
mod._ct_chest_conversions_this_level = 0
-- v0.7.55: per-level Belakor altar tracker. Same story — read and set by the
-- _spawn_guaranteed_pickup hook in _ct_pickup_spawn_owner.lua, reset at the top of
-- the consolidated populate_pickups hook (alongside the conversion counter).
mod._ct_belakor_altar_spawned_this_level = false
mod:hook("PickupSystem", "populate_pickups", function(func, self, ...)
    mod._ct_chest_conversions_this_level = 0
    -- [ct-probe] v0.7.157-dev unconditional cursed-chest budget probe (Issue #60).
    -- Fires ONCE per mission load (populate_pickups is per-mission on the host).
    -- Logs the level key + the configured cursed_chest_count (effective_setting,
    -- host-synced). The ACTUAL number spawned is reported per-spawner by the
    -- baked_cursed_chest=ALLOW/SUPPRESS + pedestal probes in _spawn_guaranteed_pickup;
    -- grep [ct-probe] and count ALLOWs to verify "actual == configured" next session.
    -- Raw printf (misc_util.lua:29) bypasses the VMF mod-logging toggle, so this
    -- lands even on a logging-OFF host (the gap that produced zero lines on Rain's).
    pcall(function()
        local cur0 = LevelHelper and LevelHelper:current_level_settings()
        local cc_raw = effective_setting("cursed_chest_count")
        local cc_cap = (cc_raw == -1 or cc_raw == nil) and 1 or cc_raw
        printf("[ct-probe] populate level=%s cursed_chest_count=%s effective_cap=%s",
            tostring(cur0 and cur0.level_id), tostring(cc_raw), tostring(cc_cap))
    end)
    -- v0.7.97: reset per-run counters for career-exclusive pickup denials.
    -- populate_pickups fires once at mission-load on the host, so this is the
    -- "run boot" hook for spawn telemetry. The denial count / once-per-run log
    -- gating live in the `_can_spawn` hook below.
    _set_career_exclusive_denial_counts({})
    _set_career_exclusive_logged_this_run({})
    -- v0.7.85 defensive logging: surface why a mission ended up with no pickups.
    -- Symptom seen 2026-05-22: Horn of Magnus run had no health/ammo/tomes/grimoires
    -- spawn. Vanilla PickupSystem.populate_pickups (pickup_system.lua:405) early-
    -- bails if `level_settings.pickup_settings` is nil, with no log. This block
    -- logs the level_key + presence of pickup_settings + game_mode at every entry
    -- so the next occurrence is diagnosable from the log alone instead of needing
    -- a fresh repro session.
    local cur = LevelHelper and LevelHelper:current_level_settings()
    local level_key = cur and cur.level_id
    local has_settings = cur and cur.pickup_settings and true or false
    local mechanism = cur and cur.mechanism
    local active_mutators = {}
    -- Vanilla API: GameModeManager._mutator_handler is a MutatorHandler instance.
    -- MutatorHandler:activated_mutators() returns self._mutators, a name-keyed
    -- table of {template = ..., context = ...} entries.
    local ok = pcall(function()
        local gm = Managers and Managers.state and Managers.state.game_mode
        local mh = gm and gm._mutator_handler
        local mutators = mh and mh:activated_mutators()
        if mutators then
            for name in pairs(mutators) do
                active_mutators[#active_mutators + 1] = name
            end
        end
    end)
    table.sort(active_mutators)
    -- v0.7.182-dev: printf, NOT mod:info. The mod:info form of this line logged ZERO times
    -- in every session (the user runs VMF mod-logging OFF), so the recurring "Horn of Magnus
    -- has no pickups" bug (first seen 2026-05-22) could never be diagnosed from a log — the
    -- data the comment above promised was silently suppressed. Raw printf is unconditional and
    -- fires once per mission load on the host (where populate_pickups runs), so it is now
    -- ALWAYS captured automatically, no debug toggle or dump command needed. has_pickup_settings
    -- =false is the smoking gun: vanilla populate_pickups (pickup_system.lua:405) early-bails on
    -- nil pickup_settings -> no health/ammo/tomes/grimoires spawn. difficulty included because
    -- the engine also warns "NO PICKUP DATA FOR CURRENT DIFFICULTY".
    local difficulty
    pcall(function()
        difficulty = Managers and Managers.state and Managers.state.difficulty
            and Managers.state.difficulty:get_difficulty()
    end)
    -- v0.7.187-dev (#58/#156): also capture the injection GATE + difficulty-entry
    -- presence. on_injected_adventure_level()==false on a magnus_/military_/etc. CW
    -- level means the whole adventure->deus pickup bridge in _can_spawn is skipped and
    -- EVERYTHING (chests, altars, ammo, healing) is vetoed -- the prime suspect for the
    -- "Horn of Magnus spawns nothing" bug. diff_has_entry==false reproduces the vanilla
    -- "NO PICKUP DATA FOR CURRENT DIFFICULTY ... USING SETTINGS FOR EASY" fallback.
    -- on_injected_adventure_level / adventure_base_from_level_key are file-locals
    -- defined LATER (forward ref -> nil global from here) -> reach via mod._ (call-time).
    local _inj, _adv_base = false, nil
    pcall(function()
        if mod._ct_on_injected_adventure_level then _inj = mod._ct_on_injected_adventure_level() end
        if mod._ct_adventure_base_from_level_key then _adv_base = mod._ct_adventure_base_from_level_key(level_key) end
    end)
    local diff_has_entry = (cur and cur.pickup_settings and difficulty
        and cur.pickup_settings[difficulty] ~= nil) and true or false
    -- v0.7.200-dev (#156): spawner-list counts at populate ENTRY. The 2026-07-01 forensics
    -- showed 100% spawn debt with ZERO pedestal probes — meaning the spawner lists were
    -- EMPTY when populate ran (pickup_gizmo_spawned never registered a unit; object-set
    -- exclusion hypothesis). These three counts close that diagnosis loop in one line:
    -- all-zero on an injected level = the level's pickup gizmos never spawned (level-load
    -- problem, see the GameModeHelper.get_object_sets hook); nonzero = the veto is
    -- downstream in _can_spawn/settings. Field names verified against vanilla
    -- pickup_system.lua:64/75/76 (guaranteed_/primary_/secondary_pickup_spawners).
    local sp_primary, sp_secondary, sp_guaranteed = -1, -1, -1
    pcall(function()
        sp_primary    = type(self.primary_pickup_spawners) == "table" and #self.primary_pickup_spawners or -1
        sp_secondary  = type(self.secondary_pickup_spawners) == "table" and #self.secondary_pickup_spawners or -1
        sp_guaranteed = type(self.guaranteed_pickup_spawners) == "table" and #self.guaranteed_pickup_spawners or -1
    end)
    pcall(printf, "[populate_pickups] level=%s mechanism=%s difficulty=%s has_pickup_settings=%s diff_has_entry=%s injected=%s adv_base=%s active_mutators=[%s] spawners: primary=%d secondary=%d guaranteed=%d",
        tostring(level_key), tostring(mechanism), tostring(difficulty), tostring(has_settings),
        tostring(diff_has_entry), tostring(_inj), tostring(_adv_base),
        table.concat(active_mutators, ","), sp_primary, sp_secondary, sp_guaranteed)
    -- [ct:456] book-spawner census on any ct injected-catalog level (Adventure AND CW),
    -- so an empty first-Grimoire spot on skaven_stronghold ("Into the Nest") is pinned to
    -- (a) spawner never registered / (b) triggered-list / (c) guaranteed-but-fails. See the
    -- _ct_book_spawner_census definition. Forward-ref safe via mod._ (call-time resolve);
    -- `self` here is the live PickupSystem.
    pcall(function()
        if mod._ct_adventure_base_from_level_key and mod._ct_adventure_base_from_level_key(level_key)
            and mod._ct_book_spawner_census then
            mod._ct_book_spawner_census(self, level_key)
        end
    end)
    -- Arm the unconditional spawn census for THIS mission (emits ~8s later via mod.update).
    if mod._ct_tally_reset then mod._ct_tally_reset(level_key, _inj, _adv_base, difficulty) end
    if not LevelHelper then
        return func(self, ...)
    end

    -- v0.7.42: effective_setting so each peer's populate_pickups mutation uses host's values.
    -- v0.7.65: sentinel -1 = "Default" (use vanilla random/count) — distinct from 0 which means
    -- "literally zero." `as_count(-1) = 0` for the altar TOTAL sum (a Default altar contributes
    -- 0 to the override total) but `altar_custom` triggers on ANY non-sentinel value.
    local function _as_count(v) return (v == -1) and 0 or v end
    local upgrade_c    = effective_setting("chest_upgrade_count")    or -1
    local swap_melee_c = effective_setting("chest_swap_melee_count") or -1
    local swap_ranged_c= effective_setting("chest_swap_ranged_count")or -1
    local power_up_c   = effective_setting("chest_power_up_count")   or -1
    local altar_total = _as_count(upgrade_c) + _as_count(swap_melee_c) + _as_count(swap_ranged_c) + _as_count(power_up_c)
    local altar_any_explicit = upgrade_c ~= -1 or swap_melee_c ~= -1 or swap_ranged_c ~= -1 or power_up_c ~= -1
    local cursed_count_raw = effective_setting("cursed_chest_count") or -1
    local cursed_count = _as_count(cursed_count_raw)
    local arena_ammo_raw = effective_setting("arena_ammo_count") or -1
    local arena_ammo = _as_count(arena_ammo_raw)
    local potions_on = effective_setting("enable_campaign_potions")  -- v0.7.64: now host-synced

    -- Defensive cleanup: if a previous populate_pickups call errored mid-flight
    -- with potions_on=true, the campaign-potion clones could remain in
    -- Pickups.deus_potions for the rest of the session. Scrub them every call
    -- when the toggle is off so subsequent missions don't see ghost potions.
    if not potions_on and Pickups and Pickups.deus_potions then
        for _, name in ipairs(_CAMPAIGN_POTION_NAMES) do
            Pickups.deus_potions[name] = nil
        end
    end

    -- v0.7.65: "custom" gates determine which fields to mutate. Sentinel -1 = "Default" =
    -- skip override. Explicit values (including 0 = literally zero) trigger override.
    -- Pre-0.7.65 the gates compared to vanilla defaults (1, 2) — that's gone because the
    -- new sentinel makes "use vanilla" the explicit choice, not "happens to match vanilla."
    local altar_custom = altar_any_explicit
    local cursed_custom = cursed_count_raw ~= -1
    local ammo_custom = arena_ammo_raw ~= -1

    -- v0.7.55: reset per-level Belakor altar tracker. Used by the tome/grim hook so
    -- only the first book spot after all Chests of Trials are placed gets the altar
    -- (one altar per mission, like vanilla belakor-themed CW levels which request
    -- `deus_02 = 1`). The altar is no longer requested via populate_pickups primary
    -- (which placed it in a random ammo/healing spot); routing through book spots
    -- means it shares the same pedestal a chest would have used, per user spec.
    mod._ct_belakor_altar_spawned_this_level = false

    -- #143: on injected adventure levels we still need to renormalize the grenade pool
    -- (Morgrim's over-spawn fix, below), so do NOT early-bail there even with no
    -- altar/cursed/ammo/potion override active. _inj was computed above (call-time via
    -- mod._ct_on_injected_adventure_level(), forward-ref safe).
    if not altar_custom and not cursed_custom and not ammo_custom and not potions_on and not _inj then
        return func(self, ...)
    end

    -- CLARIFY: Detect arena (finale) vs normal levels. Arena levels have no `deus_weapon_chest` key
    -- but DO have `ammo`; normal levels have `deus_weapon_chest` and `deus_cursed_chest`. The
    -- detection lets one hook handle both level types correctly.
    local saved = {}
    local current = LevelHelper:current_level_settings()
    local pickup_settings = current and current.pickup_settings
    if pickup_settings then
        for _, difficulty_data in pairs(pickup_settings) do
            if type(difficulty_data) == "table" and difficulty_data.primary then
                local primary = difficulty_data.primary
                local is_arena = primary.deus_weapon_chest == nil
                local entry = { tbl = primary }

                if not is_arena then
                    if altar_custom and primary.deus_weapon_chest ~= nil then
                        entry.deus_weapon_chest = primary.deus_weapon_chest
                        primary.deus_weapon_chest = altar_total
                    end
                    if cursed_custom and primary.deus_cursed_chest ~= nil then
                        entry.deus_cursed_chest = primary.deus_cursed_chest
                        primary.deus_cursed_chest = cursed_count
                    end
                elseif ammo_custom and primary.ammo ~= nil then
                    entry.ammo = primary.ammo
                    primary.ammo = arena_ammo
                end

                -- CLARIFY: Only push to `saved` if at least one field was mutated, so the restore
                -- loop below is a no-op for unchanged entries.
                if entry.deus_weapon_chest ~= nil or entry.deus_cursed_chest ~= nil or entry.ammo ~= nil then
                    saved[#saved + 1] = entry
                end
            end
        end
    end

    local added_potions = {}
    -- Saved spawn_weightings keyed by pickup_name. We renormalize the entire deus_potions
    -- group below so the inserted campaign potions are actually reachable by the sampler;
    -- both the inserts AND the originals get restored after vanilla populate_pickups runs.
    local saved_weights = {}
    if potions_on and Pickups and Pickups.deus_potions and Pickups.potions then
        -- Step 1: insert campaign potion clones using their NATIVE Pickups.potions weight
        -- (so each entry contributes ~0.33 to the running total). We'll renormalize after.
        for _, name in ipairs({ "damage_boost_potion", "speed_boost_potion", "cooldown_reduction_potion" }) do
            if Pickups.potions[name] and not Pickups.deus_potions[name] then
                local clone = table.clone(Pickups.potions[name])
                Pickups.deus_potions[name] = clone
                added_potions[#added_potions + 1] = name
            end
        end

        -- Step 2: renormalize ALL entries in Pickups.deus_potions so they sum to 1.0.
        -- Without this, the sampler in pickup_system.lua _spawn_spread_pickups picks
        -- random[0,1) and breaks on first cumulative >= random — entries past
        -- cumulative 1.0 are unreachable. CW potions were already normalized to sum
        -- ~1.0 at engine startup; adding 3 campaign entries pushed the total to ~1.375
        -- and made some entries (depending on `pairs` iteration order, which is
        -- unspecified in Lua 5.1) silently never spawn.
        local total = 0
        for name, settings in pairs(Pickups.deus_potions) do
            if settings and settings.spawn_weighting then
                saved_weights[name] = settings.spawn_weighting
                total = total + settings.spawn_weighting
            end
        end
        if total > 0 then
            for name, settings in pairs(Pickups.deus_potions) do
                if saved_weights[name] then
                    settings.spawn_weighting = saved_weights[name] / total
                end
            end
        end
    end

    -- #143: Morgrim's Bomb (holy_hand_grenade) over-spawn fix. The morgrim143 census
    -- proved every Morgrim's appearance is source=spawner -- the vanilla spread-pool
    -- sampler (pickup_system.lua:481-497) walking Pickups.grenades by spawn_weighting.
    -- We HALVE holy_hand and hand the freed half to the OTHER grenades PROPORTIONALLY, so
    -- the pool SUM is byte-identical to vanilla. That preserves the sampler invariant
    -- (running total must reach the [0,1) roll); the v0.7.143 crash (total < roll) happened
    -- only because that build LOWERED the total -- a sum-preserving redistribution provably
    -- cannot reintroduce it. Scoped to injected adventure levels (_inj) and RESTORED after
    -- vanilla populate runs, so vanilla Adventure and real CW arenas are untouched.
    local saved_grenade_weights = nil
    if _inj and Pickups and Pickups.grenades and Pickups.grenades.holy_hand_grenade
            and Pickups.grenades.holy_hand_grenade.spawn_weighting then
        local holy = Pickups.grenades.holy_hand_grenade
        local holy_orig = holy.spawn_weighting
        local sum_others, count_others = 0, 0
        for name, s in pairs(Pickups.grenades) do
            if name ~= "holy_hand_grenade" and s and s.spawn_weighting then
                sum_others = sum_others + s.spawn_weighting
                count_others = count_others + 1
            end
        end
        -- Guard: if holy_hand is the ONLY grenade there is nowhere to move the freed
        -- weight -- halving it would SHRINK the total and risk the sampler crash. Skip.
        if holy_orig > 0 and sum_others > 0 and count_others > 0 then
            saved_grenade_weights = {}
            for name, s in pairs(Pickups.grenades) do
                if s and s.spawn_weighting then saved_grenade_weights[name] = s.spawn_weighting end
            end
            local freed = holy_orig * 0.5
            holy.spawn_weighting = holy_orig - freed
            for name, s in pairs(Pickups.grenades) do
                if name ~= "holy_hand_grenade" and s and s.spawn_weighting then
                    s.spawn_weighting = s.spawn_weighting + freed * (s.spawn_weighting / sum_others)
                end
            end
            -- printf (NOT mod:info -- user runs VMF logging OFF): after_sum MUST equal the
            -- pre-change sum (holy_orig + sum_others), proving no total change -> no crash.
            local after_sum = 0
            for _, s in pairs(Pickups.grenades) do
                if s and s.spawn_weighting then after_sum = after_sum + s.spawn_weighting end
            end
            pcall(printf, "[ct:morgrim143] grenade pool renorm: holy_hand %.4f -> %.4f, freed %.4f to %d others (pool sum %.4f -> %.4f)",
                holy_orig, holy.spawn_weighting, freed, count_others, holy_orig + sum_others, after_sum)
        end
    end

    -- v0.7.165-dev: build the coin-reservation set BEFORE vanilla populate runs its
    -- _spawn_spread_pickups pass (which calls _can_spawn). The spawner lists are fully
    -- populated by now (pickup_gizmo_spawned fires per-spawner at level spawn, long
    -- before populate_pickups). Rank-based so even a tiny pool reserves >= 1 spawner.
    --
    -- Built unconditionally on the host (not gated on on_injected_adventure_level()
    -- here -- that file-local is defined LATER in this file and a lexical forward
    -- reference from this earlier hook would resolve to a nil global, per
    -- feedback_lua_forward_reference.md). Building it on a non-injected level is inert:
    -- the reservation only *takes effect* inside _can_spawn, whose entire deny block --
    -- including the reservation branches -- is already gated behind
    -- `if not on_injected_adventure_level() then return ok end`. So a set built off a
    -- vanilla level is simply never consulted. (mod._ct_rebuild... is resolved at call
    -- time, by which point the assignment below the helper has run.)
    if self.is_server and mod._ct_rebuild_coin_reserved_set then
        mod._ct_rebuild_coin_reserved_set({ self.primary_pickup_spawners, self.secondary_pickup_spawners })
    elseif mod._ct_clear_coin_reserved_set then
        mod._ct_clear_coin_reserved_set()
    end

    local results = { func(self, ...) }

    for _, entry in ipairs(saved) do
        local primary = entry.tbl
        if entry.deus_weapon_chest ~= nil then primary.deus_weapon_chest = entry.deus_weapon_chest end
        if entry.deus_cursed_chest ~= nil then primary.deus_cursed_chest = entry.deus_cursed_chest end
        if entry.ammo ~= nil then primary.ammo = entry.ammo end
    end

    -- Restore CW potion weights to their pre-renormalization values, then drop the
    -- inserted campaign clones. Order matters: restore first so we don't briefly leave
    -- weights in an inconsistent state if anything else reads Pickups.deus_potions.
    for name, original in pairs(saved_weights) do
        local entry = Pickups.deus_potions[name]
        if entry then entry.spawn_weighting = original end
    end
    for _, name in ipairs(added_potions) do
        Pickups.deus_potions[name] = nil
    end

    -- #143: restore vanilla grenade weights after populate's spread-pass consumed them,
    -- leaving Pickups.grenades pristine for the next level (vanilla Adventure / real CW).
    -- Mirrors the deus_potions save/restore above.
    if saved_grenade_weights then
        for name, original_w in pairs(saved_grenade_weights) do
            local entry = Pickups.grenades[name]
            if entry then entry.spawn_weighting = original_w end
        end
    end

    -- v0.7.126-dev (Issue #58): post-populate diagnostic dump. Fires on EVERY level
    -- including vanilla Adventure mode (Horn of Magnus, etc.) so we can capture
    -- the "working" baseline and diff against the broken CW variant. This is the
    -- single best moment in the load cycle to inspect spawners: vanilla populate
    -- has finished assigning units to spawner lists + categorizing them, and our
    -- _spawn_guaranteed_pickup conversion hook hasn't fired yet (that happens
    -- AFTER populate, during the guaranteed-spawn pass). Gated on VMF debug
    -- logging (via _dbg) so it's free in normal play.
    pcall(_dump_pickup_system_state,    "[ct_dbg][pickups:post_populate]", false)
    pcall(_dump_pickup_spawners_verbose, "[ct_dbg][pickup_units:post_populate]")

    -- v0.7.107-dev nil-hole audit: PickupSystem.populate_pickups (pickup_system.lua:395)
    -- returns nothing — every observed code path is a bare `return` or implicit end.
    -- The `results` table is therefore always empty, so bare unpack is a no-op return
    -- and equivalent to `return`. Left as-is per audit (no nil-hole exposure exists).
    return unpack(results) -- unpack-safe: results always empty, equivalent to bare return
end)

end

return install
