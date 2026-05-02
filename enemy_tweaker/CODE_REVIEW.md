# Enemy Tweaker Code Review (2026-05-01)

Scope: `enemy_tweaker/` excluding `bundleV2/`. Reviewed against
`Vermintide-2-Source-Code/scripts/managers/conflict_director/*` and
`scripts/game_state/components/enemy_package_loader.lua`.

Files reviewed:
- `enemy_tweaker/enemy_tweaker.mod`
- `enemy_tweaker/itemV2.cfg`
- `enemy_tweaker/resource_packages/enemy_tweaker/enemy_tweaker.package`
- `enemy_tweaker/scripts/mods/enemy_tweaker/enemy_tweaker.lua` (665 lines pre-comments)
- `enemy_tweaker/scripts/mods/enemy_tweaker/enemy_tweaker_data.lua`
- `enemy_tweaker/scripts/mods/enemy_tweaker/enemy_tweaker_localization.lua`
- `enemy_tweaker/CHANGELOG.md`
- `enemy_tweaker/SKELETON_HORDES.md`

## Summary

Two distinct features in one mod:
1. **Horde composition presets + breed substitution** (mature-looking, mostly OK
   but with two functional bugs — see (B1) and (B2)).
2. **Skeleton breed cloning + horde injection** (architecturally risky — see
   (B3) which is likely a hard crash on first spawn).

No forward-reference bugs. No localization escape bugs. Hooks use string-form
correctly. Settings IDs match between data and localization. The single
biggest concern is **(B3): NetworkLookup.breeds metatable error on custom
breed serialization** — needs in-game verification before this mod is shipped.

Health: dev-quality v0.2.2, two confirmed code defects, one architectural
risk. Not ready for public release.

## Confirmed bugs / potential bugs

**(B1) `_apply_preset_to_pacing_keys` drops `loaded_probs` —
`enemy_tweaker.lua:430` / now annotated**
When a preset is applied we replace `HordeCompositionsPacing[key]` with a
deep-copy of preset_variants and only restore `sound_settings`. The original
`loaded_probs` field (built at file-load by
`scripts/settings/conflict_settings.lua:636` via `LoadedDice.create`) is gone.
`horde_spawner.lua` then reads `composition.loaded_probs` at lines 139, 243,
349, 743 (`LoadedDice.roll_easy(composition.loaded_probs)` ->
`LoadedDice.roll_easy(nil)` -> `nil[1]` crash). The next ambush / vector blob
/ event horde will crash. Fix: compute `new_variants.loaded_probs` from the
new variant weights:
```lua
local weights = {}
for i, v in ipairs(new_variants) do weights[i] = v.weight end
new_variants.loaded_probs = { LoadedDice.create(weights) }
```

**(B2) `compose_horde_spawn_list` hook is a no-op —
`enemy_tweaker.lua:527`**
The vanilla function returns `(sum, sum_a, sum_b)` (three integers). It pushes
breed names into module-local upvalues `spawn_list_a` / `spawn_list_b` which
are popped via `HordeSpawner:pop_random_*`. Our hook iterates `result[i]` over
a number — does nothing — and only returns 1 of the 3 expected values. Net
effect: ambush hordes are never breed-swapped, only vector-blob hordes are.
Hook `HordeSpawner.spawn_unit` (line 1228) and substitute the `breed_name`
argument before the original runs.

**(B3) NetworkLookup.breeds metatable error on custom skeletons —
`enemy_tweaker.lua:156` (the unconditional `_register_skeleton_breeds()`
call) — annotated POTENTIAL BUG**
`scripts/network_lookup/network_lookup.lua` builds `NetworkLookup.breeds`
from `Breeds` then runs an `init` finalizer that (a) builds the reverse
`name -> index` map and (b) installs `__index = function(_, key) error(...) end`
that raises on any unknown key. VMF mods load AFTER network_lookup
finalization, so our `et_necro_skeleton`, `et_ghost_skeleton_*` etc. are
absent from both directions of the lookup. Any code path that does
`NetworkLookup.breeds[breed.name]` for these breeds (e.g.
`scripts/network/game_object_initializers_extractors.lua:178` and 17 other
sites in that file when serializing AI husk creation across the network)
will crash with `[NetworkLookup.lua] Table breeds does not contain key: et_necro_skeleton`.

This needs in-game verification — hosting solo with `et_necro_skeleton` set
as a breed_swap target may avoid network sync briefly, but as soon as a
client joins (or the host sends an `ai_unit_spawned` RPC) it will crash.

Possible mitigations (in order of likelihood-to-work):
- (a) Use existing `chaos_skeleton` breed name and swap base_unit + inventory
  on the spawned unit (visual-only) — keeps NetworkLookup happy.
- (b) Inject our names into `NetworkLookup.breeds` BEFORE the metatable is
  installed — likely impossible from a VMF mod since network_lookup runs
  during boot.
- (c) Hook the network init or replace the metatable post-hoc with a
  permissive one — fragile, may break sync.

**(B4) `et_status` reports stale redirect count — `enemy_tweaker.lua:649`
annotated POTENTIAL BUG**
`mod:echo("Package redirects: %d", next(PACKAGE_REDIRECT) and #SKELETON_BREEDS or 0)`
prints either 6 (constant) or 0. If e.g. `pet_skeleton_armored` source breed
isn't loaded (DLC gating) the redirect map has 5 entries but the status
prints 6.

**(B5) Mid-session re-enable adds breeds without threat value —
`enemy_tweaker.lua:556` annotated**
`mod.on_enabled` calls `_register_skeleton_breeds()` which inserts new
entries into `Breeds`. The threat-value seeding only happens inside the
`ConflictDirector.init` hook, which fires once per level. So toggling the
mod on mid-mission adds breeds whose `threat_values[name]` is nil; if the
performance manager ever counts one as activated, the multiplication in
`ConflictDirector.calculate_threat_value:2323` does nil arithmetic.

**(B6) Size multiplier silently discarded when preset = "off" —
`enemy_tweaker.lua:441` annotated**
`_apply_horde_preset` early-returns when no preset is selected, so the
"Horde Size %" slider never applies on its own. If that's intentional, the
tooltip should say "applies on top of preset only".

## Open questions

- Does `EnemyPackageLoader` ref-count cleanly when two breed names map to
  the same package via `_breed_package_name`? See annotation at
  `enemy_tweaker.lua:172`. Spawning `et_necro_skeleton` and a vanilla
  `pet_skeleton` (e.g. via Necromancer career summons) in the same session
  may double-load or double-unload. Needs verification.
- Should the breed-swap dropdown include the custom skeleton breeds as
  swap targets? Currently `breed_options` in `_data.lua` is hand-curated
  vanilla-only.
- Is `breed.race = "undead"` correct for damage interactions? Vanilla
  `chaos_skeleton` has `race = "chaos"` (verify); switching to "undead"
  may affect anti-undead trinkets / Sister of the Thorn AoE.

## Refactor / cleanup candidates

- **`FACTION_SKAVEN` / `FACTION_CHAOS` / `FACTION_BEASTMEN`** at lines 11-49
  are dead — defined, never read. Either consume them in `_data.lua`'s
  `breed_options` (drop the parallel hand-curated list there) or delete.
- `_status` hard-codes faction labels for `et_dump_breeds` output; could
  share a single source-of-truth with `breed_options`.
- `HORDE_PRESETS` is a flat hash with `.compositions` per preset; the
  `compositions.all` vs `compositions.skaven|chaos|beastmen` branch in
  `_apply_horde_preset` is asymmetric (`all_elites` is the only preset
  using per-faction compositions). If that ends up being the only one,
  consider dropping `compositions.all` and forcing per-faction always —
  cleaner mental model.

## Doc/code mismatches

- `DEVELOPMENT.md` table lists Enemy Tweaker's "VMF Console Prefix" as
  `(n/a)` — but the mod registers four `et_*` console commands. The actual
  in-game prefix used is `enemy_tweaker` (the full mod ID). Update
  DEVELOPMENT.md to either say `enemy_tweaker <command>` or split the
  doc field into "Mod ID" vs "command prefix".
- `SKELETON_HORDES.md` documents the design but doesn't note the
  NetworkLookup.breeds metatable issue (B3). If the design is kept, that
  caveat belongs in the doc.
- `CHANGELOG.md` is a stub directing to git log — fine, per task brief.

## Settings coherence

All four `mod:get` reads have matching widget definitions and localization
entries:

| `mod:get` key | data.lua | localization.lua |
| :--- | :--- | :--- |
| `horde_preset` | dropdown | yes |
| `horde_size_multiplier` | numeric | yes (with `%%` escape) |
| `breed_swap_from` | dropdown | yes |
| `breed_swap_to` | dropdown | yes |

Group widgets `horde_group`, `breed_swap_group` are localized.

Tooltips use `_tooltip` suffix consistently. `%%` percent-escape is correctly
applied on the one entry that needs it (`horde_size_multiplier`).

No orphans, no missing localization keys.

## Hook patterns

All three game-class hooks use string-form, matching CLAUDE.md guidance:
- `mod:hook("EnemyPackageLoader", "_breed_package_name", ...)` 
- `mod:hook("ConflictDirector", "init", ...)` 
- `mod:hook("HordeSpawner", "compose_horde_spawn_list", ...)` 
- `mod:hook("HordeSpawner", "compose_blob_horde_spawn_list", ...)` 

No table-form hooks needed; no `BackendUtils`-style plain tables involved.
No use of `mod:hook_safe` — every hook calls through to `func`. Correct
choice for transformation hooks.

## Spawn timing correctness

- **Horde preset application:** runs at the end of `ConflictDirector.init`
  (per-mission). Compositions are mutated AFTER the original `init` runs,
  so the director's own setup (which iterates compositions and primes
  `loaded_probs` per session) is intact — except we then drop those probs
  (B1).
- **Breed substitution:** runs every time `compose_blob_horde_spawn_list`
  returns a list. No timing issue there. The `compose_horde_spawn_list`
  hook is a no-op (B2) so ambush-breed substitution doesn't happen at all.
- **Skeleton breeds:** registered at mod load AND re-attempted in
  `ConflictDirector.init` hook. Threat values seeded only in init hook.

**Network/host correctness:** No host-only check anywhere. Mutating
`HordeCompositionsPacing` on a client is harmless (host runs spawn logic),
but `Breeds[name] = clone` runs on every peer including clients. If a
client doesn't have the mod and the host does, the host's RPC will reference
breed names the client can't decode — which loops back to (B3). The mod is
implicitly *required by all peers* without enforcing it.

## Breed substitution

Looks safe in isolation:
- `_build_swap_map` filters `swap_from == swap_to` and "off" sentinels.
- `_apply_breed_swap` checks `rawget(_G, "Breeds") and Breeds[replacement]`
  before substituting — won't insert an unknown breed name into spawn_list.
- The swap targets the spawn_list returned by `compose_blob_horde_spawn_list`,
  which IS a fresh array per-call (allocated inside the function body).
  Mutation in-place is safe.

But the bracket lookup `Breeds[replacement]` is the standard *mutable*
`Breeds` global, not `ItemMasterList` — there's no `__index` crashify trap
here, so `Breeds[name]` returning nil is fine. No safety issue analogous
to ItemMasterList.

## Persistence / lifecycle

- `_original_compositions_pacing` and `_original_compositions` are captured
  once (guarded by `if not _original_*`), then never re-captured. Good — if
  another mod also mutates compositions, we capture the post-other-mod
  state, but that's the right behaviour for "restore to what was here when
  WE arrived".
- `_restore_compositions` runs at every `on_setting_changed`, `on_disabled`,
  and inside `ConflictDirector.init`. This is the right pattern: re-apply
  on every transition.
- **Skeleton breeds are not deregistered on disable.** `mod.on_disabled`
  restores compositions and clears `_breed_swap_map`, but the entries in
  `Breeds`, `BreedActions`, and `PACKAGE_REDIRECT` linger. Likely
  intentional (re-enable wants them back), and harmless if the breeds
  never spawn — but the threat_value seeding doesn't clean up either.

## Console commands

Four commands are registered via `mod:command(...)`:

| Command | Purpose |
| :--- | :--- |
| `et_dump_breeds` | Lists `Breeds` keyed by `race`, with flags |
| `et_dump_compositions` | Lists `HordeCompositionsPacing` keys + variant counts |
| `et_status` | Prints current preset, multiplier, swap, skeleton flag |
| `et_check_skeletons` | Verifies the 6 skeleton clones registered |

The in-game prefix is `enemy_tweaker` (the mod ID), so usage is
`enemy_tweaker et_status`. The `et_` command-name prefix duplicates that —
consider dropping it (commands would be `dump_breeds`, `status`, etc.). Not
a bug, just verbose. Worth documenting the prefix in DEVELOPMENT.md (see
Doc/code mismatches above).

## Non-obvious things now clarified

- `HordeCompositionsPacing[key].sound_settings` is the only field worth
  preserving across replacement — `loaded_probs` is the OTHER one we missed
  (see B1).
- `compose_horde_spawn_list` (no `_blob`) returns numbers, not a list —
  easy to misread as symmetrical with the blob version.
- `HordeSpawner.spawn_unit` (line 1228) is the only spot that turns a
  string breed_name into an actual `Breeds[breed_name]` lookup for ambush
  hordes — that's the right hook target for ambush breed substitution.
- `NetworkLookup.breeds` is finalized with an error-on-missing metatable
  during boot, before VMF mods load. Adding entries to `Breeds` after that
  is "free" for non-network code (`Breeds[name]` is direct rawget) but
  fatal as soon as the engine network-serializes the breed name.
- `EnemyPackageLoader._breed_package_name` caches per-instance, so the
  redirect hook fires once per breed per session and the cached entry
  remains correct on later calls.

## Dead code

- `FACTION_SKAVEN`, `FACTION_CHAOS`, `FACTION_BEASTMEN` — unused (annotated).
- `mod.on_setting_changed`'s `setting_id` parameter is ignored — fine, but
  could be used to short-circuit when a non-relevant setting changes.

## Notes for future AI agents

1. **Forward-reference audit passed.** All locals are referenced from below
   their definition. Maintain that on edits.
2. **(B3) is the make-or-break finding.** Don't claim this mod works in
   multiplayer without first verifying NetworkLookup.breeds doesn't blow
   up when a custom skeleton spawns. Solo-host with a friend joining is
   the minimum smoke test.
3. **(B1) is testable solo.** Set any preset, start a level, wait for the
   first horde — if you hear a horde sound and then nothing spawns / game
   crashes, that's loaded_probs.
4. **`HordeCompositionsPacing.huge_armor`** etc. are referenced by string
   in `PACING_KEYS_*` — verify these keys still exist in
   `horde_compositions_pacing.lua` before relying on them. Versus / weave
   variants (e.g. `large_vs`) are intentionally NOT in our key lists.
5. **Don't hook `HordeSpawner.compose_horde_spawn_list` for return-value
   mutation.** It returns numbers. Hook `spawn_unit` for ambush breed
   substitution.
6. **Adding new presets:** they need entries in `HORDE_PRESETS`,
   `enemy_tweaker_data.lua` dropdown options, AND a localization label
   for the dropdown text — though VMF will fall back to the raw value if
   localization is missing, you get an unlocalized key in the menu.
7. **The mod ID is `enemy_tweaker` (long form), not a short prefix.**
   Console commands invoke as `enemy_tweaker et_status` not `et et_status`.
   Update DEVELOPMENT.md "VMF Console Prefix" column accordingly.
