# enemy_tweaker — Spawn-Parity Expansion Plan

**Drafted:** 2026-05-14
**Starting from:** v0.3.2-dev
**Goal:** match Spawn Tweaks' enemy/spawn-related feature set, organized cleaner, with per-difficulty control as the default.

Companion to `CODE_REVIEW.md` (2026-05-01) and `SKELETON_HORDES.md`. This doc captures scope, organization, phases, and open questions. Updated as decisions land.

---

## 1. Scope

**In scope** — enemy-side spawn/composition/stat tuning. Spawn Tweaks features filtered to enemy-related, mutators excluded per user direction.

**Out of scope** (explicitly excluded):
- All player-side features: friendly fire, player damage multipliers, white-HP behavior, recruit damage cap, bots, restart-on-defeat
- Potions / pickups: KEEP_GIVING_*, MAP_PICKUPS_*
- Buffs: PASSIVE_BUFF_*
- **Mutators**: UPSCALE_BREEDS, REVERSE_TWINS, JUICED_SPECIALS, SCARY_ELITES — these are spawn-related but feel like behavior mutators, not tuning. Stay in Spawn Tweaks territory.

---

## 2. Current state (v0.3.2-dev)

| Feature | Status | Notes |
|---|---|---|
| Horde composition presets (Faction:/Theme:) | ✓ live | global today; migration to per-difficulty in Phase 0/1 |
| Horde size multiplier | ✓ live | global today; migration to per-difficulty |
| Breed substitution (from → to) | ✓ live | global today; migration to per-difficulty |
| Custom skeleton breeds (4 necro + 2 ghost) | ✓ live | breed-creation logic stays; spawn weights become per-difficulty |
| Specials control per-difficulty (Max Total, Max Same, weights, disable) | ✓ live | reference pattern for everything else |
| Shared catalog module `enemy_tweaker_breeds.lua` | ✓ live | extend to cover all breeds, not just specials |

**Open from CODE_REVIEW.md** (verify before Phase 1):
- **B1**: `_apply_preset_to_pacing_keys` drops `loaded_probs` → `LoadedDice.roll_easy(nil)` crash on next horde
- **B2**: `compose_horde_spawn_list` hook iterates `result[i]` over a number; ambush breed-swap is a no-op; returns 1 of 3 expected values

Both pre-date the 0.3.x release; not noted as fixed in CHANGELOG. Phase 1 piggybacks on the same hooks, so these must be verified and fixed if still present.

---

## 3. Spawn Tweaks feature inventory (in-scope)

| # | Feature | What it does | In ET today? |
|---|---|---|---|
| 1 | Per-breed enable/disable | Remove a breed from the eligible spawn pool | partial (lords only) |
| 2 | Per-breed ambient weight | Weight in roaming/ambient pool | ✗ |
| 3 | Per-breed chaos-horde weight | Weight when chaos horde rolls | ✗ |
| 4 | Per-breed skaven-horde weight | Weight when skaven horde rolls | ✗ |
| 5 | Per-breed custom-horde weight | Weight for custom-faction horde slot | ✗ |
| 6 | Per-breed health multiplier | Scales breed HP (100 = vanilla) | ✗ |
| 7 | Per-breed damage-dealt multiplier | Scales outgoing damage | ✗ |
| 8 | Per-breed damage-taken multiplier | Scales incoming damage (the warning's culprit) | ✗ |
| 9 | Per-breed stagger-resist multiplier | Scales stagger thresholds | ✗ |
| 10 | Ambient count target + density multiplier | Global ambient population | ✗ |
| 11 | Ambient passivity | Roaming enemies don't engage | ✗ |
| 12 | Boss event frequency | Tunes how often boss events fire | ✗ |
| 13 | Always-specials | Specials cap always full | ✗ |
| 14 | Aggro patrols at start | Patrols immediately engage | ✗ |
| 15 | Disable lord group | Remove mini-bosses entirely | ✗ |
| 16 | Lord damage multiplier | Lord/boss damage scaling | ✗ |
| 17 | Lords aren't defensive | Behavior: lords act offensive | ✗ |
| 18 | Per-lord enable | Pick which mini-boss variants can roll | ✗ |
| 19 | Special-attack failure rates | Assassins / corruptors / packmasters fail their attack | ✗ |
| 20 | Disable specific spawn types | Loot rat, vector-blob horde | ✗ |
| 21 | Filthborn group toggle | Weakened mini-enemy grouping | ✗ |

---

## 4. Organization model

**Default: per-difficulty.** User direction: "if you don't know, assume it's tied to difficulty." Default for every new setting is per-difficulty (7 buckets: Recruit / Veteran / Champion / Legend / Cataclysm / Cataclysm 2 / Cataclysm 3), defaults seeded from VT2's vanilla per-difficulty data wherever it exists.

**Carve-outs to global** — only for settings 100% not difficulty-tied. Provisional candidates pending verification during implementation:
- *None identified yet at planning time.* When implementing each feature, default to per-difficulty unless there's a clear engine-side reason it must be global.

**Scale awareness.** Going full per-difficulty for every breed × stat is ~3,800 widgets in the settings tree. This is intentional and acceptable per user direction; UI lives in deeply-nested VMF group widgets. Future ergonomic helpers (console commands like `/et_copy_difficulty <from> <to>`) noted as Phase 5 polish.

### Proposed UI tree

Feature-axis at the top level, difficulty as the inner grouping (matches the existing Specials pattern).

```
Enemy Tweaker
├── Horde Composition (existing — migrate to per-diff)
│   └── (per-difficulty collapsibles) → size mult | preset | per-breed horde weights
├── Per-Breed Stats (new)
│   └── (per-difficulty)
│       └── (per-faction: Skaven / Chaos / Beastmen / Other)
│           └── (per-breed: Enable | Health | Dmg Dealt | Dmg Taken | Stagger | Ambient W | Skv Horde W | Chaos Horde W | Custom Horde W)
├── Specials (existing — keep)
├── Specials Behavior (new, per-diff)
│   └── Always-specials | Assassin fail % | Corruptor fail % | Packmaster fail %
├── Patrols & Lords (new, per-diff)
│   └── Aggro patrols | Disable lord group | Lords aren't defensive | Per-lord enable (8 lords) | Lord damage mult
├── Ambient & Boss Pacing (new, per-diff)
│   └── Ambient count | Density mult | Ambient passive | Boss event freq
├── Spawn Type Disables (new, per-diff)
│   └── Disable loot rat | Disable vector blob horde | Filthborn group toggle
├── Breed Substitution (existing — migrate to per-diff)
│   └── (per-difficulty) From → To pairs
└── Skeleton Hordes (existing — migrate skeleton-spawn-weight to per-diff)
```

---

## 5. Implementation phases

**Phase 0 — Verify foundations** (1–2 days)
- Confirm B1 and B2 against current source. Fix if still present.
- Unpack `SpawnTweaks.zip` (at `steamapps/workshop/content/552500/3656730554/SpawnTweaks.zip`) and reference its hook points for Phase 1–4.
- Audit `enemy_tweaker_breeds.lua` to ensure it can cover ALL breeds (lords, ambients, hordes), not just specials.

**Phase 1 — Per-breed multipliers, per-difficulty (#6–9)** (4–6 days)
- Hook `DamageUtils.calculate_damage` and `DamageUtils.add_damage_network*` (same as Spawn Tweaks does — see source) for damage-dealt and damage-taken multipliers
- Mutate `Breeds[name].max_health` and `stagger_resist` at difficulty-resolution time, restore on revert
- Save-and-restore pattern à la ct's Khaine's Fury so disabling the mod reverts cleanly
- Per-difficulty resolution via existing `Managers.state.difficulty:get_difficulty()` pattern from v0.3.1

**Phase 2 — Per-breed spawn weights & enable/disable, per-difficulty (#1–5)** (4–6 days)
- Hook `compose_horde_spawn_list` / `compose_blob_horde_spawn_list` — must first fix B2 since it breaks ambush horde swap entirely
- Hook `breed_packs.lua` ambient breed selection
- Per-breed enable acts as a "weight = 0" sugar in horde rolls and a hard filter in ambient/special pools
- `<breed>_custom_horde_weight` precedent: research from Spawn Tweaks source — looks like it feeds a custom horde slot they synthesize, not a vanilla path

**Phase 3 — Specials behavior & spawn-type disables, per-difficulty (#11, #13, #14, #19, #20, #21)** (3–4 days)
- `SpawnerSystem._try_spawn_breed` hook for type-level disables (loot rat, vector blob horde) and filthborn
- Special-attack failure: hook each special's attack-start AI brain function; per-difficulty roll vs failure %
- Always-specials: hook `SpecialsPacing` minimum cap (per-difficulty cap target)

**Phase 4 — Patrols, lords, ambient & boss pacing, per-difficulty (#10, #12, #14, #15–18)** (4–5 days)
- Patrol-aggro: hook `spawn_patrol` / `roaming_patrol`
- Lord settings: gate `Lords` table at level-load via mission_id matching
- Ambient count/density: `breed_packs` and `ConflictDirector:update`
- Boss event frequency: `TerrorEvents` pacing data (per-difficulty)
- Lord damage multiplier: piggyback on Phase 1 damage hook with lord-breed gate

**Phase 5 — Migrate existing features to per-difficulty + polish** (2–3 days)
- Horde size multiplier → per-difficulty
- Horde preset → per-difficulty
- Breed substitution → per-difficulty (from→to pairs duplicated per difficulty)
- Skeleton horde toggles → per-difficulty
- Console command `/et_copy_difficulty <from> <to>` (ergonomic helper)
- Console command `/et_reset_difficulty <diff>` (back to vanilla defaults)
- DEVELOPMENT.md update
- Localization complete pass
- Verified-state doc (matching the ct pattern)

**Total estimate: ~3 weeks of focused work** (revised up from 2 weeks since per-difficulty for everything multiplies scope vs. the original split proposal).

---

## 6. Risk register

| Risk | Severity | Mitigation |
|---|---|---|
| Widget count (~3,800) makes settings menu unusable in practice | MED | Heavy collapsible nesting; helper console commands; consider a "preset" save/load system in Phase 5+ |
| B1 / B2 from CODE_REVIEW.md still present and break horde-related features | MED | Phase 0 verification before any horde work |
| Cross-mod compat with Spawn Tweaks itself if user runs both | MED | Hook the same functions; document load order or detect+disable conflicting features |
| Lobby-hash compatibility (same as ct's `inject_adventure_maps`) | LOW | None of these features mutate `LevelSettings`; per-breed weight changes don't enter the hash. Verify during Phase 1. |
| Damage multipliers (#7, #8) replicate the exact warning the user just saw from SpawnTweaks ("Excessive adjustment may cause MP issues") | LOW | Surface the same warning when extreme values are set; document in tooltip |

---

## 7. Open questions / decisions deferred

- **Filthborn (#21)** — feature is in Spawn Tweaks but its mechanics aren't fully understood at planning time. Phase 3 needs a small research subtask before committing.
- **Custom horde weight (#5)** — `<breed>_custom_horde_weight` semantic in Spawn Tweaks unclear without source read; need to confirm whether it's a 4th horde type or a config injection point.
- **Multiplayer host/client model** — every setting is host-controlled per ct/wt/gt convention. Confirm no client-side state is needed for any of these spawn changes. Per-difficulty resolution happens server-side via `Managers.state.difficulty:get_difficulty()` which is host-authoritative.

---

## History

- **2026-05-14** — Initial plan drafted. Scope locked: mutators out, per-difficulty as default, 5-phase implementation. Verified bugs from CODE_REVIEW (B1, B2) carry forward as Phase 0 gates.
- **2026-05-14 (later)** — Phase 0 complete. B1 fixed at `enemy_tweaker.lua:468` (`_build_loaded_probs` helper, applied in `_apply_preset_to_pacing_keys`). B2 fixed via better approach: hooked `HordeSpawner.spawn_unit` (line 590) at per-unit spawn site instead of the unhookable composition function — catches blob + ambush hordes uniformly. SpawnTweaks source unpacked to `.spawn_tweaks_ref/`. Breed catalog extension (LORDS, AMBIENT/CRITTERS, role predicates) carried into Phase 1 as a prep task. No carryover bugs.
