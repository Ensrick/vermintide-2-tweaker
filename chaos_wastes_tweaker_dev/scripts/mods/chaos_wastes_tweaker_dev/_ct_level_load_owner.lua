--[[
_ct_level_load_owner - the Chaos Wastes LEVEL LOAD and MISSION START seam
(#1159 / #2 file-size refactor).

RESPONSIBILITY
Owns everything ct does in the window between "a Chaos Wastes mission's level
begins loading" and "the local player's mission has started". Three things happen
in that window and all three live here:
  * MAKE THE LOAD SURVIVABLE. Two vanilla crash predicates fire only in this
    window, both because an ADVENTURE-authored level (or an adventure-derived
    conflict director) is being loaded under the deus mechanism:
      - `EnemyPackageLoader.setup_startup_enemies` forces `use_random_directors`
        true for any injected adventure base AND for the native `_belakor_path`
        family, so `_resolve_breed_packages` populates `_random_director_list`
        and `main_path_spawning_generator.lua:314` stops dereferencing nil.
      - `MutatorHandler.tweak_pack_spawning_settings` strips the
        adventure-incompatible pack mutators (today: `no_roamers`) from BOTH the
        zone list and the mutator list whenever `pack_spawning_settings` has no
        `difficulty_overrides` - the exact field `mutator_no_roamers` iterates
        with `pairs()` - or the level is an injected adventure. The v0.7.241
        arity fix (the hook is STATIC, no leading `self`) is part of the moved
        code and stays byte-identical.
  * MAKE THE LOADED LEVEL LOOK CURSED. `_CURSE_LIGHT_PALETTES` + `_palette_slot`
    + the tint loop inside `GameModeDeus.local_player_game_starts` recolour every
    `Light` component in the level from a per-god weighted palette, deterministic
    on light index so the look is stable across reloads.
  * REPORT WHAT THE LOAD PRODUCED. `_dump_pickup_system_state`,
    `_dump_pickup_spawners_verbose` and `_ct_book_spawner_census` are the census
    built to answer "this injected map spawned nothing" (#58 Magnus, #456 Into
    the Nest, #52 / #156 object sets), plus the `[ct:136]` per-peer mission:start
    line that makes a host/client wrong-mission divergence diffable from two logs.

Extracted from chaos_wastes_tweaker_dev.lua entry lines 3946-4539. ONE contiguous
chunk moved. Every line inside it is byte-identical to the pre-extraction entry
region - MD5 `e45bf3e32d6175ef2740fb899beb576b` over the 594 raw / 570 non-empty
lines, verified against a pristine `git archive` checkout, with ZERO deviations.
The only additions are this header, the ctx binding block, the exports table and
the closing `end` / `return install`. `mod:dofile` is not a singleton, so the
entry calls this installer EXACTLY once.

ZERO LOAD-ORDER DEVIATION
The installer sits at the exact line the moved region occupied - immediately after
the consolidated `_G.Localize` hook and immediately before the
`NetworkedFlowStateManager._num_states` leak fix - so every hook in the mod still
registers in its original relative order. Nothing was reordered, split, or skipped.

HOOKS OWNED (each hooked EXACTLY ONCE in the whole mod - VMF silently drops a
second registration on the same (Class, method) pair)
  EnemyPackageLoader.setup_startup_enemies      [hook]
  MutatorHandler.tweak_pack_spawning_settings   [hook]
  GameModeDeus.local_player_game_starts         [hook_safe]
No RPC, no `mod:command`, no `_rt_register` moved with this slice. The mod-wide
hook census is unchanged by the move: 126 distinct (Class, method) pairs, each
registered exactly once, measured before and after by two independent methods
(statement-position scan and comment-stripped whole-file scan) against a pristine
`git archive` checkout.

NOT A NETWORK OWNER
The settings-sync, graph-snapshot and peer-manifest chunked transports all live
far ABOVE this region in the entry (entry lines 1084-2129) and are untouched by
this slice: the extraction removes only lines 3946-4539, so every transport line
keeps its original line NUMBER as well as its bytes. Proven mechanically - the
whole entry prefix through line 3945 is byte-identical to pristine except the
single `MOD_VERSION` line, and each transport region carries its own SHA.

CROSS-FILE CONTRACT
Entry file-locals the moved chunk closed over, and how each crosses. Every READ
crossing binds to the SAME NAME the chunk already used, which is what lets those
lines stay byte-identical:
  ctx.dbg                            entry :99, a `local function` never
      -> local _dbg                  reassigned and declared far ABOVE this
                                     install site, so it crosses BY VALUE. A
                                     late-binding wrapper would add a call frame
                                     to a per-light logging path for no gain.
                                     Same treatment `_ct_regression` already gets.
  ctx.on_injected_adventure_level    entry :3654 / :3644, both `local function`
  ctx.adventure_base_from_level_key  declarations ABOVE this install site and
      -> same-named locals           never reassigned, so they cross BY VALUE and
                                     the module holds the SAME function objects
                                     `_ct_curse_lighting_owner` (entry :4655) and
                                     `_ct_spawn_eligibility_owner` receive. Passing
                                     wrappers instead would silently give this
                                     owner a different identity for the same gate.
                                     They stay entry-owned because four owners plus
                                     `DeusMapScene.on_enter` read them; this file is
                                     a consumer, not their home.
`mod` is the installer's first parameter, exactly as the other ct owners take it.

THE THREE FORWARD-DECLARED CENSUS SLOTS
`_dump_pickup_system_state`, `_dump_pickup_spawners_verbose` and
`_ct_book_spawner_census` were entry forward-declarations (entry :803 / :804 /
:808) whose bodies - `function _name(...)`, deliberately WITHOUT `local` - were
assigned inside this region. That forward-reference pattern is load-bearing: the
`PickupSystem.populate_pickups` consumer is created ABOVE the assignment, so a
plain `local function` there would leave it capturing a nil global (the v0.7.133
burn, `feedback_lua_forward_reference.md`).

The pattern is PRESERVED, not removed - this file re-declares the three slots in
its own header below, so each moved `function _name(...)` line stays byte-identical
and assigns a module-scope local instead of an entry-scope one. Nothing leaks to
`_G`. The two `_dump_*` bodies are then handed back through the exports table and
the entry assigns its OWN forward-declared slots from them, because two consumers
still read the entry local by name:
  * `_ct_pickup_population_owner` (entry :3594-3595) takes late-binding wrappers
    over the entry locals. Its install site is ABOVE this one, so the wrappers are
    still mandatory and still resolve correctly - they now read a slot this file
    filled rather than one the entry filled in place.
  * `_ct_regression` (entry :5892-5893) takes them BY VALUE at a site below this
    one, and its `pickup_dump_forward_decls_bound` check asserts both are functions
    at chunk scope AND absent from `_G`. Both assertions still hold.
`_ct_book_spawner_census` had no such entry-local reader - its only consumer,
`_ct_pickup_population_owner`, resolves `mod._ct_book_spawner_census` off `mod` at
CALL time - so its entry forward-declaration is retired with the code, and the
`mod._ct_book_spawner_census = _ct_book_spawner_census` publication moves here
unchanged.

EXPORTS (install-time return value)
  dump_pickup_system_state             -> entry :803 forward-decl slot
  dump_pickup_spawners_verbose         -> entry :804 forward-decl slot
  adventure_incompatible_pack_mutators -> the SAME table object the entry passes
                                          to `_ct_regression` as
                                          `adventure_incompatible_pack_mutators`
                                          (entry :5897), so the
                                          `adventure_pack_compat_strip` check still
                                          inspects the live strip list, not a copy.
The two marker globals the moved code sets - `CT_NO_ROAMERS_DEUS_FIX_MARKER` and
`CT_NO_ROAMERS_ARITY_FIX_MARKER` - stay plain `_G` globals assigned by this file at
the same point in load order, which is what `_ct_regression`'s
`adventure_pack_compat_strip` and `no_roamers_strip_arity_356` read at call time.
`mod._ct_book_spawner_census` is published off `mod`, unchanged.

COMPOSES WITH, DOES NOT OVERLAP, THE NEIGHBOURING ct OWNERS
  * `_ct_curse_lighting_owner` owns the curse SKY: map/mission shading profiles
    driven through the single `CameraManager.shading_callback` hook
    (`ShadingEnvironment.set_vector3` on skydome / sun / fog keys). This file owns
    the per-unit `Light.set_color` tint applied once at mission start. Different
    hook, different engine surface, different lifetime - the sky profile is
    re-applied every frame by vanilla's shading callback, the light tint is a
    one-shot write at `local_player_game_starts`. Neither reads the other's state,
    and the split is the pre-existing one: the sky owner's own header documents
    that `Light.set_color` cannot reach skies, which is why both exist.
  * `_ct_pickup_population_owner` owns `PickupSystem.populate_pickups` - the
    BUDGET and the per-mission tally. This file owns only the census FUNCTIONS it
    calls, and calls them itself once at mission start. No hook is shared.
  * `_ct_pickup_spawn_owner` owns `_spawn_pickup` / `_spawn_guaranteed_pickup` -
    WHAT materializes. This file never spawns or rewrites a pickup; it counts.
  * `_ct_diag_skull52` owns the `#52` object-set census and is invoked from the
    `GameModeHelper.get_object_sets` hook, which stays in the entry with the
    injected-level predicates. This file never touches object sets.
  * `_adventure_pool` decides WHICH levels are injected; this file only asks,
    through the two predicates handed in via ctx.
Nothing here may read a boon, a price, a coin balance or a graph node: the level
load seam is independent of the run economy and stays that way.

Owned by: chaos_wastes_tweaker_dev.lua entry point.
Guarded by: qa/lua/tests/test_ct_level_load_owner.lua,
qa/lua/tests/test_ct_entry_decomposition.lua, the `adventure_pack_compat_strip` /
`no_roamers_strip_arity_356` / pickup forward-declaration checks in
_ct_regression.lua, the ct_dev rows of qa/rt_textual_invariants.psd1, and the
EnemyPackageLoader / MutatorHandler / GameModeDeus rows in
chaos_wastes_tweaker_dev/ENGINE_SURFACE.md.
]]

local function install(mod, ctx)

assert(type(ctx) == "table", "_ct_level_load_owner requires a context table")
assert(type(ctx.dbg) == "function",
    "_ct_level_load_owner requires ctx.dbg (entry _dbg, bound by value)")
assert(type(ctx.on_injected_adventure_level) == "function",
    "_ct_level_load_owner requires ctx.on_injected_adventure_level (entry predicate, bound by value)")
assert(type(ctx.adventure_base_from_level_key) == "function",
    "_ct_level_load_owner requires ctx.adventure_base_from_level_key (entry resolver, bound by value)")

-- The moved chunk below calls `_dbg(...)`, `on_injected_adventure_level()` and
-- `adventure_base_from_level_key(...)` unqualified, exactly as it did in the
-- entry. Binding the ctx values to those same names is what lets those lines
-- stay byte-identical across the move.
local _dbg = ctx.dbg
local on_injected_adventure_level = ctx.on_injected_adventure_level
local adventure_base_from_level_key = ctx.adventure_base_from_level_key

-- The entry's forward-declaration pattern, preserved at module scope. The three
-- `function _name(...)` definitions below deliberately carry no `local`, so they
-- assign THESE slots. Declaring them here (rather than converting the definitions
-- to `local function`) is what keeps every moved line byte-identical AND keeps all
-- three off `_G` - `_ct_regression` asserts both properties.
local _dump_pickup_system_state
local _dump_pickup_spawners_verbose
local _ct_book_spawner_census

-- DeusMechanism.uses_random_directors returns false (deus_mechanism.lua:909) so
-- EnemyPackageLoader._random_director_list stays nil for the entire CW run. Vanilla
-- CW levels' baked spawn_zone data have explicit `roaming_set` directors (no "random"
-- choice), so they never hit the nil dereference at
-- main_path_spawning_generator.lua:314 (`random_director_list[index].name`). Adventure
-- level spawn zones, however, were authored for AdventureMechanism (which returns
-- true) and DO have zone strings with "random" as one of the slash-separated
-- choices. When `process_conflict_directors_zones` picks "random" for any zone, the
-- subsequent generate_great_cycles crash fires.
--
-- Fix: force `use_random_directors = true` on the EnemyPackageLoader.setup_startup_enemies
-- call for any injected adventure level (matching by permutation base). This causes
-- _resolve_breed_packages (line 750) to populate _random_director_list, which the
-- spawn_zone generator then reads safely.
mod:hook("EnemyPackageLoader", "setup_startup_enemies", function(func, self, level_key, level_seed, failed_locked_functions, use_random_directors, conflict_director_name, difficulty, difficulty_tweak)
    -- v0.7.132-dev: also cover native CW Belakor finale maps (cemetery_belakor_path1,
    -- bell_belakor_path1, magnus_belakor_path1, ...). They carry adventure-style
    -- "random" zone directors but are NOT matched by adventure_base_from_level_key,
    -- so use_random_directors stayed false -> EnemyPackageLoader._random_director_list
    -- never populated -> vanilla main_path_spawning_generator.lua:292 crashed on nil
    -- random_director_list during generate_great_cycles (host "amand" hard crash
    -- 2026-06-06 on cemetery_belakor_path1, GUID a6d00df6-...). The `_belakor_path`
    -- key family is the signature; forcing use_random_directors true makes
    -- _resolve_breed_packages populate _random_director_list, which the spawn-zone
    -- generator then reads safely (same mechanism as the adventure-level fix above).
    if adventure_base_from_level_key(level_key)
            or (type(level_key) == "string" and string.find(level_key, "_belakor_path", 1, true)) then
        use_random_directors = true
    end
    return func(self, level_key, level_seed, failed_locked_functions, use_random_directors, conflict_director_name, difficulty, difficulty_tweak)
end)

-- v0.7.41: Adventure-injected levels use vanilla conflict directors (e.g., chaos_light)
-- whose `PackSpawningSettings` entries lack `difficulty_overrides`. CW's SIGNATURE-zone
-- pacing applies the `no_roamers` mutator (mutator_deus_pacing_tweak.lua:38) which does
-- `pairs(pack_spawning_settings.difficulty_overrides)` → "bad argument #1 to 'pairs'
-- (table expected, got nil)" on first mission entry. Vanilla CW levels all have the
-- field populated; adventure ones don't (Crashify guid 004768e7).
--
-- Vanilla intends no_roamers as a CW-only pacing tool; it's mechanically too aggressive
-- for adventure levels anyway (area_density_coefficient = 0 wipes roaming spawns). Per
-- user: replace with the gentler `deus_less_roamers` semantics OR just exempt adventure
-- levels. Simplest exemption: filter the mutator name out of the zone/mutator lists
-- before vanilla `tweak_pack_spawning_settings` processes them.
local ADVENTURE_INCOMPATIBLE_PACK_MUTATORS = {
    no_roamers = true,
}

-- v0.7.231: the strip now keys off the crash predicate (missing difficulty_overrides),
-- not only on_injected_adventure_level, so Belakor/other deus missions on adventure-derived
-- conflict directors are covered. Marker asserted by /ct_regression_test.
CT_NO_ROAMERS_DEUS_FIX_MARKER = "no_roamers_strip_keys_on_missing_difficulty_overrides_v0.7.231"

-- v0.7.241 (issue 356): ARITY FIX. Vanilla MutatorHandler.tweak_pack_spawning_settings is
-- STATIC - defined dot-form (def mutator_handler.lua:748) and DOT-CALLED with exactly 4 args
-- (zone_mutator_list, mutator_list, conflict_director_name, pack_spawning_settings) at
-- main_path_spawning_generator.lua:327. The pre-fix hook declared a spurious leading `self`,
-- so VMF's arg pass shifted every param by one: `pack_spawning_settings` always read nil (the
-- missing_field strip fired on EVERY call) and, worse, the real `zone_mutator_list` - the list
-- no_roamers actually rides on for CW SIGNATURE zones - rode in as the dropped-`self` positional
-- and was NEVER filtered. So the pairs(nil) host CTD this guard exists to prevent (crash guid
-- 4c84c68a: no_roamers reading pack_spawning_settings.difficulty_overrides on a Belakor node)
-- could still fire on signature zones. Fix: drop `self`, bind the 4 real params in vanilla
-- order, filter BOTH lists. Behavioral arity lock: /ct_regression_test `no_roamers_strip_arity_356`.
CT_NO_ROAMERS_ARITY_FIX_MARKER = "no_roamers_hook_static_arity_no_self_v0.7.241"

mod:hook("MutatorHandler", "tweak_pack_spawning_settings", function(func, zone_mutator_list, mutator_list, conflict_director_name, pack_spawning_settings)
    -- Strip the adventure-incompatible pack mutators (no_roamers) when EITHER:
    --   (a) pack_spawning_settings lacks `difficulty_overrides` -- the exact field
    --       no_roamers iterates with pairs() (mutator_no_roamers.lua:6), so letting it
    --       run fatals `bad argument #1 to 'pairs' (table expected, got nil)`. This is
    --       the precise crash predicate and ALSO covers deus missions running on
    --       adventure-derived conflict directors like `chaos_light` that lack the field
    --       -- e.g. a Belakor node (`military_belakor_path1`, conflict chaos_light /
    --       deus_skaven_chaos): crash console 2026-07-05-23.30.21, guid 4c84c68a. The
    --       v0.7.41 `on_injected_adventure_level()` check below never fires for these
    --       (they ARE deus, not injected-into-stock-Adventure), so no_roamers reached
    --       vanilla and crashed on first mission entry. OR
    --   (b) on_injected_adventure_level() -- the original v0.7.41 aesthetic exemption
    --       (no_roamers' area_density_coefficient=0 wipes roaming spawns, too aggressive
    --       for adventure geometry). Kept OR-ed so this build never strips LESS than before.
    -- On a normal CW level difficulty_overrides IS present and it isn't injected, so the
    -- guard passes through and vanilla no_roamers runs untouched. Stripping never removes
    -- a working mutator: with difficulty_overrides nil, no_roamers can only ever crash.
    local missing_field = type(pack_spawning_settings) ~= "table" or pack_spawning_settings.difficulty_overrides == nil
    if not (missing_field or on_injected_adventure_level()) then
        return func(zone_mutator_list, mutator_list, conflict_director_name, pack_spawning_settings)
    end
    local function filter(list, list_label)
        if type(list) ~= "table" then return list end
        local kept, dropped = {}, nil
        for _, name in ipairs(list) do
            if ADVENTURE_INCOMPATIBLE_PACK_MUTATORS[name] then
                dropped = dropped or {}
                dropped[#dropped + 1] = name
            else
                kept[#kept + 1] = name
            end
        end
        if dropped then
            -- [ct:356] fires only when a mutator is actually filtered. Naming the list
            -- (zone_mutator_list vs mutator_list) confirms in the field that the
            -- SIGNATURE-zone path - the one the old arity bug missed - is now covered.
            pcall(printf, "[ct:356] stripped {%s} from %s on conflict '%s' (difficulty_overrides present=%s) - prevented pairs(nil) crash in mutator_no_roamers",
                table.concat(dropped, ","), tostring(list_label), tostring(conflict_director_name),
                tostring(type(pack_spawning_settings) == "table" and pack_spawning_settings.difficulty_overrides ~= nil))
        end
        return kept
    end
    -- Filter BOTH lists in vanilla order. run_mutators processes mutator_list then
    -- zone_mutator_list (mutator_handler.lua:765-766); no_roamers can ride on either.
    return func(filter(zone_mutator_list, "zone_mutator_list"), filter(mutator_list, "mutator_list"), conflict_director_name, pack_spawning_settings)
end)

-- ============================================================
-- Curse light tinting on injected adventure levels
-- ============================================================
-- Vanilla GameModeDeus.local_player_game_starts (game_mode_deus.lua:358-378)
-- iterates `Level.units(current_level)` and applies `DeusThemeSettings[theme].light_probe_tint`
-- to lights inside reflection_probe units. For vanilla CW that's enough — the level
-- bundle's sky shader and atmosphere are theme-specific too, so the tint reinforces
-- the existing visual.
--
-- Adventure level bundles have only the native atmosphere baked in (no per-god sky).
-- So when our injected `<adv>_<theme>_path1` permutation loads under a curse, the
-- engine applies the reflection-probe tint but the sky/atmosphere remains adventure-
-- vanilla. Result: cursed adventure missions look too "normal".
--
-- Partial mitigation: hook_safe the same function and apply the theme color to
-- EVERY light in the level (not just reflection probes), plus the camera backlight.
-- This makes the curse colour shift more pronounced even on adventure geometry.
-- It can't bring back the baked sky/particles, but it makes "this node is cursed"
-- visually obvious.
-- Per-curse PALETTES instead of a single tint, so individual level lights
-- pick up complementary / accent colors and the scene reads as themed
-- atmosphere rather than a uniform color filter.
--
-- Each palette has:
--   dominant: the headline color (most lights). Hits ~50% of lights.
--   accent:   a related-but-distinct shade. ~25% of lights.
--   complement: a deliberately contrasting hue. ~15% of lights.
--   warm/cool counterpoint: ~10% of lights — adds visual depth.
--
-- Distribution uses a deterministic hash on each light's index so the look
-- is repeatable per level / per run, not random per frame. The hash is
-- coarse on purpose (a handful of buckets) so nearby lights tend to
-- group rather than producing rainbow noise.
-- Each palette balances 4-5 slots:
--   - Dominant: god's headline hue (most lights).
--   - Accent:   nearby hue, reinforces theme (some lights).
--   - Complement: TRUE opposite on the color wheel — provides contrast pop.
--                 Red↔Cyan, Green↔Magenta, Blue↔Orange, Purple↔Yellow-Green.
--   - Neutral white-ish: keeps some lights "normal-looking" so the
--     colored lights register as accents instead of saturating the scene.
--     User feedback 2026-05-14: "purple looks good with white light sources" —
--     applies broadly; neutral slot makes other palettes pop too.
local _CURSE_LIGHT_PALETTES = {
    khorne = {
        { 1.00, 0.30, 0.25, w = 40 },   -- blood red (dominant)
        { 1.30, 0.55, 0.20, w = 20 },   -- ember orange (accent — same warm family)
        { 1.10, 1.05, 0.90, w = 15 },   -- warm white candle (neutral)
        { 0.95, 0.95, 0.35, w = 10 },   -- gold flame (warm secondary pop)
        { 0.20, 0.90, 1.00, w = 15 },   -- cold cyan complement (true ↔ red)
    },
    nurgle = {
        { 0.45, 1.00, 0.40, w = 40 },   -- sickly bog green (dominant)
        { 0.95, 1.05, 0.35, w = 20 },   -- jaundiced yellow (accent)
        { 1.00, 1.00, 0.95, w = 15 },   -- pale moldy white (neutral)
        { 0.30, 0.85, 0.95, w = 10 },   -- swamp teal (cool secondary)
        -- v0.7.46: was { 1.10, 0.30, 0.95 } — bright magenta. User wanted deep
        -- dark purple instead. Reduced red and blue and dropped overall intensity
        -- so the complement slot reads as ominous violet rather than hot pink.
        { 0.45, 0.15, 0.65, w = 15 },   -- deep dark purple complement (true ↔ green)
    },
    tzeentch = {
        -- Per user feedback v0.7.16: "make all the lights and most of the
        -- natural lights a magic blue, but then have just the overarching
        -- outdoor light be a deep orange." Dropped the cool-white slot
        -- entirely so 100% of Light components are some shade of deep
        -- magic blue. The contrast is now strictly: indoor / point lights
        -- (= blue) vs. outdoor sun + ambient (= warm orange via the shading
        -- env profile below).
        --
        -- NOTE: vanilla torches that get their orange glow from PARTICLE FX
        -- and self-illumination materials (not Light components) will still
        -- look warm — Light.set_color on the unit's Light handle doesn't
        -- override particle / material colors. If the user wants those
        -- pulled cool too we need a separate hook on the particle effect
        -- registry. Not done yet — wait for user feedback to see if it
        -- matters in practice.
        { 0.15, 0.30, 1.50, w = 75 },   -- deep magic cobalt (saturated, dominant)
        { 0.25, 0.50, 1.40, w = 25 },   -- mid cobalt variant (subtle variation, still deep blue)
    },
    slaanesh = {
        { 1.20, 0.45, 1.15, w = 35 },   -- hot pink (dominant)
        { 0.65, 0.40, 1.10, w = 20 },   -- deep purple (accent)
        { 1.10, 1.05, 1.10, w = 20 },   -- pale white (USER: "purple looks good with white")
        { 1.20, 0.75, 0.50, w = 10 },   -- peach warm pop
        { 0.55, 1.10, 0.45, w = 15 },   -- yellow-green complement (true ↔ pink)
    },
    belakor = {
        { 0.40, 0.30, 0.75, w = 40 },   -- twilight purple (dominant)
        { 0.30, 0.45, 0.95, w = 20 },   -- moonlight blue (accent)
        { 0.95, 0.95, 1.05, w = 15 },   -- pale silver-white (ghostly neutral)
        { 0.55, 0.30, 0.55, w = 10 },   -- shadow violet (cool secondary)
        { 1.05, 1.00, 0.50, w = 15 },   -- pale gold complement (true ↔ violet)
    },
}

-- Pick a palette slot for light index `i`. Stable across reloads — same
-- light index always gets the same slot for a given palette. Multiplier 7
-- and offset are arbitrary; chosen so groups of adjacent indices don't all
-- fall into the same bucket (avoid "all lights in this room are blood red").
local function _palette_slot(palette, idx)
    local total_w = 0
    for s = 1, #palette do total_w = total_w + (palette[s].w or 1) end
    -- Hash idx into [0, total_w)
    local h = ((idx * 7919) + 11) % total_w
    local cum = 0
    for s = 1, #palette do
        cum = cum + (palette[s].w or 1)
        if h < cum then return palette[s] end
    end
    return palette[1]
end

-- v0.7.125-dev — pickup-system diagnostic dump (Issue #58, Magnus pickups).
-- Walks LevelSettings.pickup_settings AND PickupSystem live spawner lists,
-- counting placed level-units by spawner_type. The combination tells us
-- whether the data table is missing entries for the current difficulty
-- (settings issue) or whether the level just has no spawners (geometry
-- issue) when the engine reports "Remaining spawn debt".
--
-- Caller controls whether output goes to log only (via mod:info) or also
-- to in-game chat (via mod:echo). Returns nothing; all output is side-effect.
local _PICKUP_CATEGORIES = {
    "deus_weapon_chest", "deus_cursed_chest",
    "deus_potions", "deus_soft_currency",
    "ammo", "healing", "grenades", "level_events",
    "explosive_barrel", "frag_grenade", "fire_grenade",
}

-- audit 2026-06-07 (v0.7.133-dev): `local` dropped — assigns into the forward-
-- declared slot near the top of the file so the earlier populate_pickups hook
-- reference resolves to this upvalue instead of a nil global.
function _dump_pickup_system_state(prefix, also_echo)
    prefix = prefix or "[pickup_dump]"
    local emit = function(line)
        _dbg("%s %s", prefix, line)
        if also_echo then mod:echo(line) end
    end

    -- 1. Resolve current level + difficulty
    local level_key, difficulty_key
    pcall(function()
        local gm_mgr = Managers and Managers.state and Managers.state.game_mode
        if gm_mgr and gm_mgr.level_key then level_key = gm_mgr:level_key() end
        local diff_mgr = Managers and Managers.state and Managers.state.difficulty
        if diff_mgr and diff_mgr.get_difficulty then difficulty_key = diff_mgr:get_difficulty() end
    end)
    emit(string.format("level=%s difficulty=%s", tostring(level_key), tostring(difficulty_key)))

    -- 2. LevelSettings[level_key].pickup_settings — full per-difficulty dump
    local level_settings_root = rawget(_G, "LevelSettings")
    local ls = level_settings_root and level_key and level_settings_root[level_key]
    if not ls then
        emit("LevelSettings[level_key] = nil (cannot inspect pickup_settings)")
    else
        local ps = ls.pickup_settings
        if not ps then
            emit("level.pickup_settings = nil (level has no pickup_settings table)")
        else
            local diff_keys = {}
            for k, _ in pairs(ps) do diff_keys[#diff_keys + 1] = tostring(k) end
            table.sort(diff_keys)
            emit("level.pickup_settings keys: {" .. table.concat(diff_keys, ",") .. "}")
            local matching = ps[difficulty_key]
            if not matching then
                emit(string.format(
                    "NO MATCH for current difficulty='%s' in pickup_settings — engine will fall back. "
                    .. "This is the root signal for Issue #58.",
                    tostring(difficulty_key)))
            end
            -- For each difficulty present, dump the primary counts
            for _, dk in ipairs(diff_keys) do
                local entry = ps[dk]
                if type(entry) == "table" and type(entry.primary) == "table" then
                    local p = entry.primary
                    local parts = {}
                    for _, cat in ipairs(_PICKUP_CATEGORIES) do
                        if p[cat] ~= nil then
                            parts[#parts + 1] = string.format("%s=%s", cat, tostring(p[cat]))
                        end
                    end
                    for k, v in pairs(p) do
                        local known = false
                        for _, cat in ipairs(_PICKUP_CATEGORIES) do if k == cat then known = true; break end end
                        if not known then
                            parts[#parts + 1] = string.format("%s=%s", tostring(k), tostring(v))
                        end
                    end
                    emit(string.format("  [%s].primary { %s }", dk, table.concat(parts, ", ")))
                end
            end
        end
    end

    -- 3. PickupSystem live spawner lists, counted by spawner_type
    local entity_mgr = Managers and Managers.state and Managers.state.entity
    local ps_sys = entity_mgr and entity_mgr.system and entity_mgr:system("pickup_system")
    if not ps_sys then
        emit("PickupSystem unavailable (entity manager not ready)")
        return
    end

    local function count_by_type(list)
        local total, by_type = 0, {}
        if type(list) ~= "table" then return total, by_type end
        for _, unit in pairs(list) do
            total = total + 1
            if Unit and Unit.alive and Unit.alive(unit) then
                for _, cat in ipairs(_PICKUP_CATEGORIES) do
                    if Unit.get_data and Unit.get_data(unit, cat) then
                        by_type[cat] = (by_type[cat] or 0) + 1
                    end
                end
            end
        end
        return total, by_type
    end

    local function emit_list(name, list)
        local total, by_type = count_by_type(list)
        local parts = {}
        for _, cat in ipairs(_PICKUP_CATEGORIES) do
            if by_type[cat] then parts[#parts + 1] = string.format("%s=%d", cat, by_type[cat]) end
        end
        emit(string.format("PickupSystem.%s total=%d { %s }", name, total, table.concat(parts, ", ")))
    end

    emit_list("primary_pickup_spawners",   ps_sys.primary_pickup_spawners)
    emit_list("secondary_pickup_spawners", ps_sys.secondary_pickup_spawners)
    emit_list("specified_pickup_spawners", ps_sys.specified_pickup_spawners)
    emit_list("guaranteed_pickup_spawners", ps_sys.guaranteed_pickup_spawners)

    -- triggered_pickup_spawners is keyed by triggered_spawn_id
    if type(ps_sys.triggered_pickup_spawners) == "table" then
        local trig_total, group_count = 0, 0
        for _, group in pairs(ps_sys.triggered_pickup_spawners) do
            group_count = group_count + 1
            if type(group) == "table" then
                for _ in pairs(group) do trig_total = trig_total + 1 end
            end
        end
        emit(string.format("PickupSystem.triggered_pickup_spawners groups=%d total_units=%d", group_count, trig_total))
    end
end

-- v0.7.126-dev — verbose per-spawner-unit dump. Captures world position + every
-- truthy Unit.get_data(unit, key) for each placed spawner unit, so we can
-- diff a "working" mission (vanilla magnus in Adventure) against a "broken"
-- mission (magnus_belakor_path1 in CW) and see which spawner categories the
-- bundle actually ships on each level. Capped at 50 units per list — typical
-- adventure level has 30–80 spawners; cap keeps the log readable while still
-- giving 50 worked examples per category.
local _VERBOSE_DUMP_CAP_PER_LIST = 50
-- audit 2026-06-07 (v0.7.133-dev): `local` dropped — assigns into the forward-
-- declared slot near the top of the file (see _dump_pickup_system_state note).
function _dump_pickup_spawners_verbose(prefix)
    prefix = prefix or "[pickup_units]"
    local entity_mgr = Managers and Managers.state and Managers.state.entity
    local ps_sys = entity_mgr and entity_mgr.system and entity_mgr:system("pickup_system")
    if not ps_sys then return end

    local function dump_one(list_name, list)
        if type(list) ~= "table" then return end
        local idx = 0
        for _, unit in pairs(list) do
            idx = idx + 1
            if idx > _VERBOSE_DUMP_CAP_PER_LIST then
                _dbg("%s   %s ... (truncated at %d units)", prefix, list_name, _VERBOSE_DUMP_CAP_PER_LIST)
                break
            end
            if Unit and Unit.alive and Unit.alive(unit) then
                local pos = "?"
                pcall(function()
                    local p = Unit.local_position(unit, 0)
                    pos = string.format("(%.1f,%.1f,%.1f)", Vector3.x(p), Vector3.y(p), Vector3.z(p))
                end)
                local tags = {}
                for _, cat in ipairs(_PICKUP_CATEGORIES) do
                    if Unit.get_data(unit, cat) then tags[#tags + 1] = cat end
                end
                if Unit.get_data(unit, "tome")     then tags[#tags + 1] = "tome"     end
                if Unit.get_data(unit, "grimoire") then tags[#tags + 1] = "grimoire" end
                if Unit.get_data(unit, "loot_die") then tags[#tags + 1] = "loot_die" end
                if Unit.get_data(unit, "painting_scrap") then tags[#tags + 1] = "painting_scrap" end
                _dbg("%s   %s[%d] pos=%s tags={%s}", prefix, list_name, idx, pos,
                    table.concat(tags, ","))
            end
        end
    end

    dump_one("primary",    ps_sys.primary_pickup_spawners)
    dump_one("secondary",  ps_sys.secondary_pickup_spawners)
    dump_one("specified",  ps_sys.specified_pickup_spawners)
    dump_one("guaranteed", ps_sys.guaranteed_pickup_spawners)
end

-- [ct:456] v0.7.249-dev — book-spawner census. Issue #456 ("Into the Nest",
-- skaven_stronghold): in a CW run the location of the FIRST Grimoire is ALWAYS empty.
-- ct's Chest-of-Trials placement converts book (tome/grimoire) pickup-spawner units to
-- deus_cursed_chest inside PickupSystem._spawn_guaranteed_pickup, so an empty book spot
-- means one of:
--   (a) the grimoire spawner UNIT never registered with PickupSystem at all — its level
--       object set is not enabled under the deus game mode (the #52 / #156 family; see the
--       [ct:skull52] object-set census + the GameModeHelper.get_object_sets #156 fix). It
--       would then be absent from EVERY spawner list here.
--   (b) it registered into the TRIGGERED list (triggered_spawn_id), whose activation flow
--       (PickupSystem.activate_triggered_pickup_spawners, pickup_system.lua:283) never fires
--       under the deus mechanism, so _spawn_guaranteed_pickup is never called for it. It
--       would then show list=triggered here but produce no conversion probe.
--   (c) it IS a guaranteed spawner that converts, but the chest/casket fails at that
--       position — the [ct:456] fallthrough probes in _spawn_guaranteed_pickup catch this.
--
-- Neither existing probe answers (a)/(b): _dump_pickup_spawners_verbose is _dbg-gated
-- (invisible on a mod-logging-OFF host) and never enumerates the triggered list per unit,
-- and the [populate_pickups] line reports only aggregate list counts. This census is
-- UNCONDITIONAL printf (misc_util.lua:29, survives logging OFF) and enumerates EVERY
-- tome/grim-tagged unit across guaranteed + primary + secondary + specified + triggered,
-- with its list, guaranteed_spawn / triggered_id flags and world position. Fires for any
-- ct injected-catalog base (MISSION_BY_KEY) in BOTH Adventure and CW, so a plain-Adventure
-- load of skaven_stronghold gives a baseline to diff the CW load against (the diff method
-- _dump_pickup_spawners_verbose was built for). Cheap: books are <=5 per level.
-- audit: `local` dropped — assigns into the forward-declared slot near the top of file.
function _ct_book_spawner_census(ps_sys, level_key)
    if not (ps_sys and Unit and Unit.get_data) then return end
    local g_tome, g_grim, t_tome, t_grim, o_tome, o_grim = 0, 0, 0, 0, 0, 0
    local function posstr(unit)
        local s = "?"
        pcall(function()
            local p = Unit.local_position(unit, 0)
            s = string.format("(%.1f,%.1f,%.1f)", Vector3.x(p), Vector3.y(p), Vector3.z(p))
        end)
        return s
    end
    local function scan(list_name, list, trig_id)
        if type(list) ~= "table" then return end
        for _, unit in pairs(list) do
            if Unit.alive and Unit.alive(unit) then
                local is_tome = Unit.get_data(unit, "tome") and true or false
                local is_grim = Unit.get_data(unit, "grimoire") and true or false
                if is_tome or is_grim then
                    local kind = is_grim and "grim" or "tome"
                    local guaranteed = Unit.get_data(unit, "guaranteed_spawn") and true or false
                    local tid = trig_id or Unit.get_data(unit, "triggered_spawn_id") or ""
                    pcall(printf, "[ct:456] book_spawner level=%s list=%s kind=%s guaranteed_spawn=%s triggered_id=%s pos=%s",
                        tostring(level_key), list_name, kind, tostring(guaranteed), tostring(tid), posstr(unit))
                    if list_name == "guaranteed" then
                        if is_grim then g_grim = g_grim + 1 else g_tome = g_tome + 1 end
                    elseif list_name == "triggered" then
                        if is_grim then t_grim = t_grim + 1 else t_tome = t_tome + 1 end
                    else
                        if is_grim then o_grim = o_grim + 1 else o_tome = o_tome + 1 end
                    end
                end
            end
        end
    end
    scan("guaranteed", ps_sys.guaranteed_pickup_spawners)
    scan("primary",    ps_sys.primary_pickup_spawners)
    scan("secondary",  ps_sys.secondary_pickup_spawners)
    scan("specified",  ps_sys.specified_pickup_spawners)
    if type(ps_sys.triggered_pickup_spawners) == "table" then
        for trig_id, group in pairs(ps_sys.triggered_pickup_spawners) do
            scan("triggered", group, trig_id)
        end
    end
    pcall(printf, "[ct:456] census level=%s books guaranteed(tome=%d grim=%d) triggered(tome=%d grim=%d) other(tome=%d grim=%d)",
        tostring(level_key), g_tome, g_grim, t_tome, t_grim, o_tome, o_grim)
end
mod._ct_book_spawner_census = _ct_book_spawner_census

mod:hook_safe("GameModeDeus", "local_player_game_starts", function(self, player, loading_context)
    -- v0.7.124-dev — per-mission diagnostic dump (Issue: citadel curse mismatch).
    -- Gated on VMF debug logging via _dbg. Runs on BOTH peers when a CW mission
    -- starts. Dumps current_node + its full state so we can compare host vs client
    -- and verify the active mutator list matches the node's expected curse.
    pcall(function()
        local rc = self._deus_run_controller
        if not rc then
            pcall(printf, "[ct:136] mission:start no _deus_run_controller (unexpected)")
            return
        end
        local rs = rc._run_state
        local is_server = (rs and rs.is_server and rs:is_server())
                          or (Managers and Managers.player and Managers.player.is_server)
                          or false
        local cur_key = rc.get_current_node_key and rc:get_current_node_key() or nil
        local cur = rc.get_current_node and rc:get_current_node() or nil
        local mutators_str = "<nil>"
        if cur and type(cur.mutators) == "table" then
            local list = {}
            for i, m in ipairs(cur.mutators) do list[i] = tostring(m) end
            mutators_str = "{" .. table.concat(list, ",") .. "}"
        end
        -- Active engine-side mutators (via MutatorHandler). Snapshot the set so we
        -- can compare against the node's `mutators` list and the displayed curse.
        local active_str = "<unavailable>"
        local game_mode_manager = Managers and Managers.state and Managers.state.game_mode
        if game_mode_manager then
            local mh = game_mode_manager._mutator_handler
            local active = mh and mh.activated_mutators and mh:activated_mutators()
            if type(active) == "table" then
                local names = {}
                for name, _ in pairs(active) do names[#names + 1] = tostring(name) end
                table.sort(names)
                active_str = "{" .. table.concat(names, ",") .. "}"
            end
        end
        -- v0.7.243-dev (#136): raw printf (was _dbg, invisible with mod-logging
        -- OFF - the user's setup). This is the per-peer resolved-mission line: run
        -- a CW expedition on host + client and diff the two [ct:136] mission:start
        -- lines for the same round. A differing level/node/god is the wrong-mission
        -- symptom the player sees; the [ct:136] graph lines (populate_graph) show
        -- the roll that caused it. injected = whether this level is an injected
        -- adventure map (the client IS_INJECTED gate that goes false in the #134/
        -- #136 divergence class); level_seed exposes the possibly-unsynced seed the
        -- client rolled its graph from.
        local injected = "<nil>"
        pcall(function() injected = tostring(on_injected_adventure_level() and true or false) end)
        pcall(printf, "[ct:136] mission:start is_server=%s current_node=%s level=%s base_level=%s theme=%s curse=%s level_seed=%s god=%s node_type=%s injected=%s node_mutators=%s active_mutators=%s",
            tostring(is_server), tostring(cur_key),
            cur and tostring(cur.level) or "<nil>",
            cur and tostring(cur.base_level) or "<nil>",
            cur and tostring(cur.theme) or "<nil>",
            cur and tostring(cur.curse) or "<nil>",
            cur and tostring(cur.level_seed) or "<nil>",
            cur and tostring(cur.god) or "<nil>",
            cur and tostring(cur.node_type) or "<nil>",
            injected, mutators_str, active_str)
    end)

    -- v0.7.125-dev — pickup-system state dump (Issue #58: Magnus pickups).
    -- Log-only (no echo) when VMF debug logging is on. Captures level
    -- pickup_settings table contents + live PickupSystem spawner counts per
    -- spawner_type. Critical for diagnosing "no chests/altars spawn" bugs.
    pcall(_dump_pickup_system_state, "[ct_dbg][pickups:mission_start]", false)

    if not on_injected_adventure_level() then return end
    local run_controller = self._deus_run_controller
    if not run_controller then return end
    local current_node = run_controller:get_current_node()
    if not current_node then return end
    local theme = current_node.theme
    if not theme or theme == "wastes" then
        _dbg("[curse-tint] theme=%s (no curse); skipping", tostring(theme))
        return
    end
    local palette = _CURSE_LIGHT_PALETTES[theme]
    if not palette then
        mod:warning("[curse-tint] no palette mapping for theme=%s", tostring(theme))
        return
    end

    local world = self._world
    local level = LevelHelper:current_level(world)
    if not level then return end

    -- DELIBERATE: don't tint the camera backlight (that was glowing the
    -- first-person hands which the user didn't want). Tint only world lights.
    local units = Level.units(level)
    local lights_tinted = 0
    local global_idx = 0
    for j = 1, #units do
        local level_unit = units[j]
        if Unit.alive(level_unit) then
            local num_lights = Unit.num_lights(level_unit)
            if num_lights and num_lights > 0 then
                for i = 1, num_lights do
                    local light = Unit.light(level_unit, i - 1)  -- 0-indexed per vanilla
                    if light then
                        global_idx = global_idx + 1
                        local slot = _palette_slot(palette, global_idx)
                        Light.set_color(light, Vector3(slot[1], slot[2], slot[3]))
                        lights_tinted = lights_tinted + 1
                    end
                end
            end
        end
    end
    _dbg("[curse-tint] level=%s theme=%s palette_size=%d lights=%d",
        tostring(current_node.level), tostring(theme), #palette, lights_tinted)
end)

-- Install-time exports. See "EXPORTS" in the header: the two `_dump_*` bodies go
-- back into the entry's own forward-declared slots (two consumers still read them
-- by entry-local name), and the strip list crosses as the SAME table object so
-- `_ct_regression`'s `adventure_pack_compat_strip` inspects the live list.
return {
    dump_pickup_system_state             = _dump_pickup_system_state,
    dump_pickup_spawners_verbose         = _dump_pickup_spawners_verbose,
    adventure_incompatible_pack_mutators = ADVENTURE_INCOMPATIBLE_PACK_MUTATORS,
}

end

return install
