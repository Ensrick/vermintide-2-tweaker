# Progressive Elite Modifiers (#323)

Status: implemented default-off in 0.7.350-dev (host-authoritative); awaiting
in-game verification. The Enemy Tweaker per-modifier/per-category branch of the
original request is tracked separately in #453.

The requested curve is mission 1 = 0%, mission 2 = 5%, mission 3 = 10%,
mission 4 = 15%, and mission 5 onward = 20%. CT derives that exactly from
`DeusRunController.get_completed_level_count()`, which increments once per won
level [src: deus_run_controller.lua:529-536], without creating a new
difficulty tier. The host setting **Elite Enhancement Chance per Completed Map**
rescales the same shape (0-25 percentage points per completed map, default 5).

## Source boundary

Ordinary `ConflictDirector` spawns receive no enhancement list. Vanilla applies
enhancements only when `optional_data.enhancements` exists
(`conflict_director.lua:2029-2042`). The grudge generator supplies a monster
`base` plus entries from the 13-member `BossGrudgeMarks` set and only bans one
specific troll/periodic-shield pair (`grudge_mark_settings.lua:126-140,191-195`).
That is not evidence that all boss buffs are safe on every elite or special.

There is one source-proven elite recipe: Geheimnisnacht's Chaos Warrior uses
`elite_base` plus either `shockwave` or `ignore_death_aura`, both in the altar
event (`geheimnisnacht_2021_generic_terror_events.lua:9-22`) and in Geheimnisnacht
Hard Mode (`mutator_geheimnisnacht_2021_hard_mode.lua:3-12,125-155`). Those two
form the whole allowlist. Their procs are breed-agnostic: the shockwave fires on
the generic AI `minion_attack_used` proc (`animation_callback_templates.lua:166,236`;
`buff_settings_grudge_marks.lua:641-649,1461-1473`) and the aura queries allies by
side and position (`buff_settings_grudge_marks.lua:650-661,1208-1265`). The other 13
remain boss-only.

## Runtime seam

`_ct_progressive_elite_runtime.lua` owns one full hook on
`ConflictDirector._post_spawn_unit`, where fresh spawns and breed-freezer reuse
both finish (`conflict_director.lua:1859-1868,2024`). It calls vanilla first, so
pre-spawn terror/cursed-chest lists (`terror_event_utils.lua:182-203`), Hard
Mode's in-pass append and vanilla's own apply (`conflict_director.lua:2034-2041`)
have all run. A unit whose payload has a list, or whose
`grudge_marked.name_index` attribute is set, is left alone. A freezer-reused unit
keeps only an emptied attribute category (`ai_system.lua:648-664,1574-1590`), so it
rolls like a fresh spawn.

CT never writes the spawn's `optional_data`. `HordeSpawner.spawn_unit` passes one
`horde.optional_data` table to every unit of a horde (`horde_spawner.lua:1236-1242`)
and the enemy recycler re-spawns deactivated units from the stored table
(`enemy_recycler.lua:662,708`), so a list left there would mark later horde trash.
CT instead calls `TerrorEventUtils.apply_breed_enhancements` with a private
per-unit table carrying the list and a deterministic `name_index`, which vanilla
would otherwise draw from the terror-event RNG (`terror_event_utils.lua:80-84`). The
call resolves the global at call time, so CT's own grudge-mark filter hook still
wraps it and prints its `[grudge-spawn]` row. Selection is a pure hash of the
spawn queue id and breed name. Buffs and attributes replicate through vanilla
`rpc_add_buff` and `rpc_set_attribute_*` identities and both replay on hot join
(`buff_system.lua:66-96,277-310`; `ai_system.lua:1592-1612,1654-1686`).

## Receipts

- `[ct:323] runtime installed activation=... rates=... hook=ConflictDirector._post_spawn_unit` once per load.
- `[ct:323] apply N/12 breed=... recipe=... spawn=... completed=... rate=...` for the
  first 12 marked elites per session.
- `[ct:323] audit=N/7 ...` on each Chaos Wastes mission exit and on
  `/ct_progressive_elite_audit`, with `rates`, `step`, `elite/selected/applied`,
  `special/selected_special/applied_special` and `activation`.
- The existing `[grudge-spawn]` row from `_ct_boss_grudge_marks.lua` names the
  applied list for every enhanced spawn.

## Verification gate

Solo first: enable the option with the step at 25, finish the first map (no marked
elites, `rate=0`), then fight elites on the second map (`rate=25`). Require
`applied_special=0`, only `elite_base` plus `shockwave` or `ignore_death_aura` in
`[grudge-spawn]` rows for ordinary elites, and `PASS` for both
`issue323_progressive_elite_runtime` and `issue323_progressive_elite_feasibility`.
Co-op/hot join follows the solo pass: a client must see the same marked elites
without running any CT selection.
