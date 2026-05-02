# Chaos Wastes Tweaker Code Review (2026-05-01)

Scope: every file under `chaos_wastes_tweaker/` except `bundleV2/`. Source-of-truth cross-checks
performed against `C:\Users\danjo\source\repos\Vermintide-2-Source-Code\` (vanilla VT2 source).

## Summary

Code quality is solid for a single-author mod. The core hooks (coin multiplier, boon disable/start,
trait filter, altar distribution, curse skip) all use the correct save-and-restore pattern around
the wrapped `func()` call, hook signatures match vanilla, and the forward-reference declaration for
`sync_reckless_swings` is set up correctly. Two real concerns: a probable but minor probabilistic
bug in the campaign-potions injection (sample-weight inflates total to ~1.375 in a sampler that
breaks at 1.0), and 40 missing tooltip localization keys causing raw `<setting_id>` strings to
display on hover. Several minor issues around error-path state leaks, dead code (a 174-line
boon-keys file is bundled but never loaded), and undocumented hardcoded array indices.

## Confirmed bugs / potential bugs

- `chaos_wastes_tweaker_localization.lua` — **40 tooltip keys missing** that are referenced by
  widgets in `_data.lua`. Hovering these widgets shows raw `<setting_id>` text instead of help.
  Specifically:
  - `disable_boon_squats_tooltip`, `start_boon_squats_tooltip`
  - `disable_boon_deus_power_up_quest_granted_test_01_tooltip`,
    `start_boon_deus_power_up_quest_granted_test_01_tooltip`
  - All 36 talent tooltips: `disable_boon_talent_N_M_tooltip` / `start_boon_talent_N_M_tooltip`
    for N=1..6, M=1..3.
  - **Severity: LOW** — visual only, no crash. Either add entries or drop `tooltip = "..."` from
    the widget defs.

- `chaos_wastes_tweaker.lua:441 (campaign potion injection)` — **Probabilistic correctness**: the
  fix sets each cloned campaign potion's `spawn_weighting` to one existing CW-potion weight
  (~0.125). After insertion, the sum of `Pickups.deus_potions[*].spawn_weighting` exceeds 1.0
  (vanilla normalized to 1.0 + ~0.375 of clones). The `pickup_system._random()` returns in `[0,1)`
  and the sampler iterates `pairs(...)` (unspecified order) breaking on first cumulative >=
  random. Entries that happen to land after the cumulative sum crosses 1.0 are unreachable.
  Behavior is therefore "campaign potions appear sometimes, depending on iteration order"
  rather than guaranteed inclusion at the intended rate. Proper fix: re-normalize ALL weights in
  `Pickups.deus_potions` after insertion, then revert on cleanup. **Severity: MED** (works in
  practice, but probability skew is hidden and can vary per Lua VM).

- `chaos_wastes_tweaker.lua:33 (setup_run starting-coins call)` — calls
  `self:on_soft_currency_picked_up(starting)` without the second `type` arg. The vanilla
  server-only branch in `on_soft_currency_picked_up` checks `type ==
  DeusSoftCurrencySettings.types.GROUND/MONSTER` and increments per-pickup counters. With nil it
  matches neither, so the player's "ground coins picked up" / "monster coins picked up" stats are
  not incremented for the starting grant. Probably intentional (starting coins aren't a pickup),
  but worth noting. **Severity: LOW**.

- `chaos_wastes_tweaker.lua:99 (boon-removal hook), :334 (trait filter hooks),
  :448 (pickup hook)` — all use **save-and-restore around `func()` without pcall**. If `func()`
  raises, restore code never runs and global tables stay mutated for the rest of the session.
  Same pattern five places. Wrapping each in `pcall` (or `xpcall`) and re-raising would harden
  this. **Severity: LOW** — vanilla doesn't normally throw in these paths but mods can.

- `chaos_wastes_tweaker.lua:514 (reckless swings)` — hard-codes `tpl.buff_template.buffs[1]`,
  `tpl.description_values[1]`, `tpl.description_values[3]`, `buff_entry.buffs[1]`. If FatShark
  reorders these arrays in a future patch, the wrong fields are mutated silently. A defensive
  version would search by `buff_to_add` name or description key. **Severity: LOW**.

- `chaos_wastes_tweaker.lua:209 (_enable_hover)` — disabled-curse path returns nothing (implicit
  nil); normal path returns whatever func returns. If a future caller relies on the return value,
  the disabled path silently differs. **Severity: LOW**.

## Open questions

- `chaos_wastes_tweaker.lua:50` — Why detect `count_index` by scanning args for an integer in
  `[1,10]`, rather than just using `args[2]`? Vanilla signature is stable
  `(seed, count, existing_power_ups, ...)`. The scan adds robustness against signature drift but
  also silently no-ops if a caller passes a count > 10.

- `chaos_wastes_tweaker.lua:118 (fix_arc_nan)` — Why only patch the 1-widget case? If the NaN can
  also occur for 0 or N>1 widgets, this silently fails to repair them. Probably tied to the
  specific division-by-zero condition in vanilla's arc layout but not documented.

- `chaos_wastes_tweaker_boon_keys.lua` — what's the intent of this file? Per CHANGELOG v0.2.5 it
  was the source for runtime-generated localization, but the current code uses static
  localization in `_localization.lua` and never loads this list.

## Refactor / cleanup candidates

- `chaos_wastes_tweaker_boon_keys.lua` — currently dead code. Either wire it up via `require`-
  equivalent and switch to runtime loc generation, or delete the file. Bundling it into
  `bundleV2/` is harmless (no `new_mod()` collision since it just `return`s a list) but it adds
  ~3KB to bundle size and confuses code archaeology.

- `chaos_wastes_tweaker.lua:572 (on_setting_changed)` — Currently only handles
  `tweak_reckless_swings`. If future Modified-Boon entries are added, this will need expanding.
  Consider a small dispatch table once there's a second entry.

- `chaos_wastes_tweaker.lua:497, 528 (apply/revert reckless_swings)` — the apply/revert pair has
  symmetric structure. Could be unified via a `tbl, key, new_value, old_value_field` data-driven
  approach to remove the parallel-mutation risk. Low priority.

- `chaos_wastes_tweaker.lua:894 (cw_status command)` — only reports altar / cursed-chest / arena
  ammo / potion settings. Doesn't reflect coin multiplier, starting coins, shrine boon count,
  god override, force_belakor, banned traits, disabled curses, disabled boons, or starting boons.
  Would be useful as a comprehensive "what's enabled?" debug.

- `chaos_wastes_tweaker.lua:582-862 (debug commands)` — `dump_boons` and `dump_buffs` define
  `dump_table` separately. Could share. Low priority — debug code seldom rerun.

## Doc/code mismatches

- `CHANGELOG.md` v0.2.5 says "Localization is generated at mod registration time from the static
  boon key list, then upgraded to actual game display names on first Chaos Wastes entry." This
  describes a runtime-generation pipeline that does NOT exist in the current source. The current
  code uses static localization in `_localization.lua` (every entry hardcoded). Either the
  changelog needs amending or the code needs to be reverted/restored to match.

- `chaos_wastes_tweaker.lua:3` — `MOD_VERSION = "0.3.0-dev"` matches the CHANGELOG top entry. OK.

- `itemV2.cfg:2` description matches in-source CHANGELOG (Khaine's Fury rename, campaign potions,
  altar dropdowns). OK.

## Settings coherence

- **Orphan setting_ids in _data**: NONE. Every `setting_id = "..."` in `_data.lua` has a
  corresponding `mod:get(...)` read in `chaos_wastes_tweaker.lua` (either directly or via the
  `disable_curse_*`, `disable_boon_*`, `start_boon_*`, `ban_trait_*` prefix patterns).

- **Missing localization for**: 40 `tooltip = "X"` references have no matching loc entry (see
  Confirmed bugs section above). All `setting_id = "X"` widgets DO have matching entries —
  it's only the tooltip extra keys that are missing.

- **Unread settings (defined but never `mod:get(...)`-ed)**: NONE among non-group widgets. All
  group setting_ids (`*_group`) are display-only headers — those are not expected to be read.

## Hook patterns

All hooks in `chaos_wastes_tweaker.lua` follow CLAUDE.md conventions:

- String-form `mod:hook("ClassName", ...)` for game classes (`DeusRunController`,
  `DeusPowerUpUtils`, `DeusShopView`, `DeusCursedChestView`, `MutatorHandler`, `DeusMechanism`,
  `DeusMapDecisionView`, `DeusWeaponGeneration`, `PickupSystem`). Correct — these are loaded lazily.
- Table-form `mod:hook(_G, "Localize", ...)` for the global Localize. Correct — `_G` is always
  available.
- `mod:hook_safe` is used for `setup_run` and `_add_initial_power_ups` where return values aren't
  needed and post-call timing is desired. Correct.
- No hooks on `BackendUtils.can_wield_item`. Correct.

Hook signatures all match vanilla:
- `DeusRunController.on_soft_currency_picked_up(self, amount, type)` → mod reads `args[1]` (amount).
- `DeusRunController.setup_run(self, run_seed, difficulty, ...)` → mod uses hook_safe and calls
  `self:on_soft_currency_picked_up(starting)`.
- `DeusPowerUpUtils.generate_random_power_ups(seed, count, ...)` → count detected by integer scan.
- `DeusRunController._add_initial_power_ups(self, peer_id, local_player_id, profile_index,
  career_index, initial_talents_for_career)` → mod hook_safe drops the 5th arg (OK for hook_safe).
- `DeusRunController.get_deus_weapon_chest_type(self)` → matches.
- `DeusMechanism._setup_run(self, run_id, run_seed, is_server, server_peer_id, difficulty,
  journey_name, dominant_god, with_belakor, mutators, boons)` → matches.
- `MutatorHandler._activate_mutator(self, name, active_mutators, mutator_context, mutator_data,
  optional_duration)` → mod intercepts only `name`, returns early to skip — correct.

## Non-obvious things now clarified

Inline `-- CLARIFY:` comments added explaining:
- Why `sync_reckless_swings` is forward-declared (Lua 5.1 forward-reference rules; was a 5x prior
  crash class).
- Coin amount is `args[1]` (was once a wrong-index bug).
- Why `granting_starting_coins` flag exists (suppresses multiplier hook re-entry).
- Why `count_index` is detected by value range (signature-drift defense).
- Why `SHRINE_DEFAULT`/`CHEST_DEFAULT` gating is needed (avoid hijacking other call sites).
- Why backward iteration in boon removal (table.remove index stability).
- Why curse save-and-restore pattern preserves theme too (curse-themed assets keyed off theme).
- Why `theme = "wastes"` forced when curse is suppressed (visual consistency).
- Why is_arena detection works (arena levels lack `deus_weapon_chest`, have `ammo`).
- Why client-only path in `_add_initial_power_ups` early-outs on `peer_id != own_peer_id`.
- Why `reckless_swings_originals` doubles as a "tweak active" flag.
- Why the description override hooks `Localize` separately (vanilla string format isn't fully
  driven by `description_values`).
- The probabilistic skew in campaign potion injection (POTENTIAL BUG).
- Why three trait-filter wrap points (covers all three vanilla call sites).
- Why `func()` error paths leak state (no pcall).

## Dead code

- `chaos_wastes_tweaker_boon_keys.lua` — entire file (174 lines, 172 boon names + bracket lines).
  Not loaded anywhere. See Refactor section for options.

- `chaos_wastes_tweaker.lua:582-863 (dump_spawners, dump_boon_loc, dump_boons, dump_buffs,
  dump_mutators)` — these are intentional debug commands, not dead code, but they are large
  (~280 lines). Worth keeping but might be a candidate for moving to a `_debug.lua` partial in a
  future refactor.

## Notes for future AI agents

- **Forward references**: `sync_reckless_swings` is correctly forward-declared on line 13 (now
  with a CLARIFY comment). If you add another helper, follow the same pattern. ALWAYS check that
  every `local function NAME` is defined ABOVE every `NAME(` call site. See
  `feedback_lua_forward_reference.md` — this has crashed the codebase 5 times.

- **Save-and-restore pattern**: The mod uses temporary mutation of global tables
  (`DeusPowerUpsArray`, `DeusWeapons`, `LevelSettings.pickup_settings`, `Pickups.deus_potions`,
  `node.curse`, `node.theme`) followed by restoration after `func()`. If you add a new save-
  and-restore hook, MIRROR the existing structure exactly. Consider adding pcall hardening if
  fragility is a concern.

- **Host vs client semantics**: Host-driven settings are gated by `is_server` in `_setup_run`
  (force_belakor, finale_dominant_god). Per-client settings (boon disables, trait bans, altar
  distribution) run on every client because the client also runs the relevant hooks during their
  own simulation. The `_add_initial_power_ups` hook explicitly demarcates host vs own-peer for
  starting boons.

- **Internal mod ID is `"ct"` (NOT `"chaos_wastes_tweaker"`)**: `new_mod("ct", ...)` is in
  `chaos_wastes_tweaker.mod`. Settings persistence depends on this ID; do NOT change it.
  `mod:get("...")` reads from the "ct" namespace.

- **Workshop ID 3712929235 is PUBLIC by intent**: per
  `feedback_workshop_metadata_user_dictates.md`, do not change `visibility` in `itemV2.cfg`
  without explicit user direction. weapon_tweaker / general_tweaker / career_tweaker are PRIVATE
  and an earlier agent flipping them to public got two mods flagged/removed-from-community
  irreversibly.

- **Hot-reload (Ctrl+Shift+R) is risky for this mod**: chaos_wastes_tweaker is Lua-only so it
  *might* survive hot-reload, but per CLAUDE.md "a restart is still safest." Especially if you
  modify the reckless-swings tweak (live monkey-patches on DeusPowerUpTemplates) or the
  Pickups.deus_potions injection (clones leak on hot-reload between hooks firing).

- **Pickups normalization runs at startup, not per-mission**: `pickups.lua:912-926` normalizes
  every group's spawn_weighting once. Adding entries to `Pickups.deus_potions` after this DOES
  NOT trigger re-normalization. The campaign-potion injection works around this by sampling an
  existing weight, but the math is approximate (see "Probabilistic correctness" bug).

- **`_get_graph_data()` (private) vs `get_graph_data()` (public)**: Both exist on
  `DeusRunController`. The mod uses `_get_graph_data()` only in the chest-distribution path; all
  other call sites use `get_graph_data()`. Lua doesn't enforce underscore privacy, so calling
  either from a hook is legal — but if you add a new hook, prefer the public version.
