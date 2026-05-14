# Chaos Wastes Tweaker Changelog

## 0.7.18-alpha (2026-05-14)

### Added: `disable_dominant_god` checkbox (default on)

The "all 4 gods rotate uniformly" behaviour from v0.7.14 is now a user-toggleable setting in the Run Structure group. Default on (matches v0.7.14+). Toggle off to restore vanilla CW's "dominant god is reserved for the finale, never appears on regular missions" rule. Independent of `cursed_mission_count` — works at any count value including 0.

### Tweaked: Curse-node exterior shading-env profiles softened (~30% pull toward neutral)

User feedback: Khorne, Nurgle, and Tzeentch exterior tints (sky / sun / ambient / fog) were "oppressive" — the outdoor color saturated the whole scene. Each value pulled approximately 30% toward neutral (1.0):

- Khorne fog `{1.55, 0.25, 0.20}` → `{1.39, 0.48, 0.44}` (less blood-bath)
- Nurgle skydome `{0.45, 1.30, 0.40}` → `{0.62, 1.21, 0.58}`
- Tzeentch sun `{1.55, 0.60, 0.20}` → `{1.39, 0.72, 0.44}` (less deep-orange punch)

Slaanesh and Belakor untouched (user said Slaanesh looks great; Belakor not flagged). Per-light point-light palettes also untouched — those are doing their job; the issue was just the overarching exterior color washing the scene.

## 0.7.17-alpha (2026-05-14)

### Tweaked: Tzeentch lights now 100% deep blue, outdoor light pushed to deep orange

User feedback v0.7.16: "more blue on tzeentch for sure — make all the lights and most of the natural lights a magic blue, but then have just the overarching outdoor light be a deep orange."

- **Per-light palette**: dropped the 10% cool-white slot. 100% of Light components are now deep magic blue (75% deepest cobalt, 25% mid cobalt variant). Caveat: vanilla torches that get their warm glow from particle FX / self-illumination materials (not from Light components) will still look warm — pulling those cool would need a separate hook on the particle effect registry. Holding off until you say it matters.
- **Outdoor shading env**: sun, secondary sun, and ambient pushed from "warm orange" to "deep orange" (R 1.40→1.55, G 0.75→0.60, B 0.35→0.20 on sun_color; same shape for ambient + ambient_top). Fog stays cool blue, sky stays cobalt. Result should read as: cobalt sky with deep-orange sunlight pouring through, hitting magic-blue rooms.

## 0.7.16-alpha (2026-05-14)

### Fixed: `terror_event_mixer.lua:1662: attempt to index a nil value` crash on adventure-injected nodes

Crash reproduced on a `nurgle_tzeentch_path1` node (Festering Ground under tzeentch theme). The level's flow fires `start_random_event("nurgle_end_event_loop")`, which evaluates `WeightedRandomTerrorEvents[level_key][event_chunk_name]` at terror_event_mixer.lua:1595. Our injected adventure permutation keys (`<base>_<theme>_path<n>`) don't have entries in `WeightedRandomTerrorEvents` (vanilla builds it from `LevelSettings` at boot, before our pool injects), so the lookup returns nil and the indexer crashes.

Same fix shape as the existing `TerrorEventBlueprints` mirror in `_adventure_pool.lua`: when injecting each permutation key, also mirror `WeightedRandomTerrorEvents[base_lvl]` to `WeightedRandomTerrorEvents[permutation_key]` if a base entry exists. Adventure end-event chunks now resolve to the same set the base adventure level uses.

## 0.7.15-alpha (2026-05-14)

### Tweaked: Tzeentch point lights are now all deep blue, no accents

v0.7.13 kept some magenta + mint in the Tzeentch per-light palette as variety. User feedback: too much mix; wants every mod-tinted point light to be deep blue, and the warm orange (already set on sun_color / ambient_tint in v0.7.13's shading env profile) to be the only source of warmth in the scene. Reduced palette to just two deep-blue variants + a tiny cool-neutral slot:

- 65% **deep cobalt** (saturated, darker than the v0.7.13 dominant — `{ 0.20, 0.35, 1.45 }`)
- 25% mid cobalt variant (`{ 0.30, 0.55, 1.35 }` — still deep blue, slightly varied)
- 10% cool white spark (`{ 1.00, 1.05, 1.15 }` — rare neutral)

No magenta, no mint, no warm orange in per-light. Vanilla torches stay warm naturally; warm orange ambient/sun comes from the shading-env profile.

## 0.7.14-alpha (2026-05-14)

### Fixed: `cursed_mission_count` override never gave Khorne curses when journey's dominant god was Khorne

User reported 4 runs in a row with no Khorne-themed cursed missions. Log confirmed: `dominant god <khorne>`, and the 13/13 cursed nodes were distributed nurgle/slaanesh/tzeentch only — the final node was the only one to receive a Khorne curse (`curse_khorne_champions` on `arena_ruin_khorne_path1`).

Root cause: vanilla `spread_curse` (deus_populate_graph.lua) reserves the dominant god exclusively for the "final" node (line 686-690) and then EXCLUDES it from the non-final rotation (line 698 — `if NO_DOMINANT_GOD or god ~= context.dominant_god then`). With dominant=khorne, the 12 non-final cursed nodes can only pick from {nurgle, tzeentch, slaanesh}.

Fix: when our count override is active, also set `config.NO_DOMINANT_GOD = true`. All 4 gods enter the uniform rotation. Final loses its "always dominant" guarantee but with `count >= total_curseable` it gets cursed anyway (by whichever god the rotation picks). Saved/restored alongside the other override fields.

## 0.7.13-alpha (2026-05-14)

### Tweaked: Tzeentch lighting — keep point lights cool, warm orange comes from sun/ambient

v0.7.11's Tzeentch palette added a 25% warm-orange complement to per-light tinting. User feedback: vanilla level torches are already warm orange, so adding more warmth to point lights double-saturates the warm channel without producing the contrast we wanted — Tzeentch nodes still read as "blue blue blue" with no real visual pop.

Better approach: keep per-light point lights all cool (blue / magenta / mint / white) and deliver the warm complement via the **sun_color + ambient_tint + secondary_sun_color** entries in the per-frame ShadingEnvironment profile. Daylight + skybounce pours warm orange across the scene; torches stay warm-orange (vanilla); magic point lights stay cool blue (mod). Net visual: cobalt sky lit by warm orange sun rays — strong color separation by light type.

Per-light Tzeentch palette is now blue-dominant: 55% cobalt blue / 20% magenta aurora / 15% cool white / 10% mint. No warm orange in the palette — that's the sky/sun's job now.

## 0.7.12-alpha (2026-05-14)

### Fixed: `cursed_mission_count` override didn't curse the very first nodes (run_progress=0)

v0.7.9-alpha lowered `CURSES_MIN_PROGRESS` to `0` so early nodes would be eligible — but vanilla's `get_nodes_above_progress` (deus_populate_graph.lua:45-55) uses **strict** `progress < node.run_progress`, so nodes with `run_progress = 0` got `0 < 0 = false` and stayed filtered out. User's v0.7.11 run: 14/16 cursed, the missing 2 were the first nodes at run_progress 0 / 0.16. Fix: set `CURSES_MIN_PROGRESS = -1` instead, so `-1 < 0 = true` and the first-mission nodes are in the candidate pool.

With `cursed_mission_count >= total_curseable`, this guarantees every node (including the first 1-2) gets a curse — what the user explicitly wanted.

## 0.7.11-alpha (2026-05-14)

### Tweaked: Curse light palettes — stronger contrast, added neutral white slot

v0.7.10's palettes were still too monotone on Tzeentch (the "cyan ice" complement was too close to its cobalt-blue dominant — visually "blue blue blue"). Rebalanced every god to:

1. **Drop dominant weight** from 50% → 35-40% so more lights pick up accents.
2. **Add a neutral white-ish slot** (15-20% of lights). User feedback that Slaanesh's purple looks good with white light sources generalizes — leaving some lights uncolored makes the colored ones register as deliberate accents instead of the whole scene saturating to one hue.
3. **Use true color-wheel complements** instead of nearby hues:
   - Khorne (red) → cold cyan (was warm gold)
   - Nurgle (green) → pustule magenta (was swamp teal — fine accent but not a complement)
   - **Tzeentch (blue) → warm orange** (was warm gold — orange is the true blue complement, 25% weight, much more contrast)
   - Slaanesh (pink) → yellow-green
   - Belakor (purple) → pale gold
4. Keep an accent slot of a related hue + a small "secondary pop" slot for visual variety in dim corners.

Distribution remains deterministic per light-index hash (`idx * 7919 + 11`), so the look is repeatable per level. The user can compare directly to v0.7.10 by re-entering the same cursed node.

## 0.7.10-alpha (2026-05-14)

### Improved: Cursed-node level lights use a per-curse palette instead of one flat tint

v0.6.x → v0.7.9 painted every level light in a cursed adventure mission the same RGB (e.g. all-blood-red for Khorne) — too monotone. Replaced with per-curse PALETTES: each god gets a dominant color plus accent / warm counterpoint / complementary contrast shades. Lights are deterministically distributed across the palette buckets (50% dominant / 25% accent / 10% warm / 15% complement), so adjacent lights tend to group but the room as a whole reads as themed atmosphere rather than monochrome.

Per-curse identity preserved:
- **Khorne**: blood red dominant, ember orange accent, gold-flame warm pop, cold steel-blue complement
- **Nurgle**: bog green dominant, jaundiced yellow accent, pustule magenta pop, swamp teal complement
- **Tzeentch**: cobalt blue dominant, magenta aurora accent, warm gold flicker, cyan ice complement
- **Slaanesh**: hot pink dominant, deep purple accent, teal yellow-green complement, peach warm pop
- **Belakor**: twilight purple dominant, moonlight blue accent, pale yellow-green ghost complement, shadow violet counterpoint

The distribution hash is stable across game loads (`(idx * 7919 + 11) % total_weight`) so the same level always lights the same way for a given curse — no per-frame rainbow noise.

## 0.7.9-alpha (2026-05-14)

### Diagnostic: cursed_mission_count=30 → 8 cursed nodes confirmed, halo invisible because of node-unit prefix matching

v0.7.8 diagnostic revealed `spread_curse` IS cursing 8 of 11 curseable nodes (so the override works); the visual is missing because `DeusMapScene.spawn_graph_units` (`scripts/ui/views/deus_menu/deus_map_scene.lua:182`) picks the 3D node mesh by string prefix on `node.level`:
- `pat_*` → TRAVEL_NODE_UNIT (has cursed-halo flow events)
- `sig_*` → SIG_NODE_UNIT
- `arena_*` → ARENA_NODE_UNIT
- else (e.g. `military_*`, `nurgle_*`, `farmlands_*`, `dlc_castle_*`) → SHRINE_NODE_UNIT (no halo flow events)

All 8 of the user's cursed nodes use adventure-injected level base names (`military` → Righteous Stand, `nurgle` → Festering Ground, etc.) which don't match any of the vanilla prefixes — so they all render as SHRINE_NODE_UNIT and the halo never appears.

The mod already has a `DeusMapScene.on_enter` hook that rewrites adventure-base level keys to `pat_<icon>_<theme>_path1` before the unit-spawn loop runs. That should fix the visual — but the diagnostic doesn't confirm whether it's firing for the user's graph. This release adds per-node log lines so v0.7.9's log will show exactly how many nodes the hook rewrites and which keys it skips.

### Fixed: `cursed_mission_count` override skips nodes below `CURSES_MIN_PROGRESS`

Same override block now also drops `CURSES_MIN_PROGRESS` to 0 for the duration of `func()`. Vanilla's filter (typically 0.2) was excluding the first 2-3 nodes of every journey from being cluster-center candidates. With `range=0` (exact count), those early nodes were guaranteed-uncursed even when the user set count=30. The user's v0.7.8 dump showed 3 uncursed nodes at progress 0/0.16/0 — all dropped by the filter. Lower it so the early run is also fair game. Saved/restored alongside the existing range/count fields.

## 0.7.8-alpha (2026-05-14)

### Diagnostic only: fix `count_cursed` to read the right field

v0.7.5 / v0.7.6's diagnostic counted nodes by `n.type == "TRAVEL"` etc., but the completed graph returned by `deus_populate_graph` uses `n.node_type` ("ingame"/"shop"/"start") — `type` only lives on the BASE graph (input). My counter never matched any node and reported `cursed=0 / total_curseable=0` on every run, including ones that almost certainly had curses applied. Switched to `n.node_type == "ingame"` and added a `dump_graph` helper that logs EVERY node (cleanly tagged) so we can see the real state. Re-run with v0.7.8 to get accurate cursed-count numbers.

## 0.7.7-alpha (2026-05-14)

### Added: `tweak_boon_movespeed` — double the Movement Speed property boon (5% -> 10%)

New checkbox in the Modified Boons group. Vanilla `MorrisBuffTweakData.movespeed` is `{ description_value = 0.05, multiplier = 1.05 }`; `deus_power_up_settings.lua` (line ~7148) bakes the multiplier into per-rarity `DeusPowerUpBuffTemplates.power_up_movespeed_{common,rare,legendary}.buffs[1].multiplier` at game load, and the description_value into `DeusPowerUpTemplates.movespeed.description_values[1].value` (shared by all rarities via reference). The tweak save-and-restores both: mutates the three per-rarity multipliers to 1.10 and the description value to 0.10. In-game tooltip auto-reflects "10%" because vanilla `description_properties_movespeed` is formatted off `description_values`. With `max_amount = 2`, two stacks compound to ~21%.

Mirrors the reckless_swings pattern: forward-declared `sync_boon_movespeed`, called from the boon-roll hook (post-call), `on_setting_changed`, and at mod load; reverted from `on_disabled` so toggling the mod off cleans up the persistent DeusPowerUpBuffTemplates / DeusPowerUpTemplates mutations.

## 0.7.6-alpha (2026-05-14)

### Diagnostic only: extended `deus_populate_graph` logging for the `cursed_mission_count` debug

v0.7.5-alpha added a `post-run cursed=N / total_curseable=M` log but only in the `replace_shrines_with_missions = OFF` branch. The user's failing scenario has the toggle ON, so the log never fired. This release moves the count + dumps every curseable node's `curse`, `god`, `progress`, and `level` so we can see exactly which nodes ended up cursed and which were skipped. No behavior change otherwise.

## 0.7.5-alpha (2026-05-14)

### Improved: Cursed-node atmosphere lighting (richer per-curse profiles)

v0.7.2-alpha's curse sky tint applied one flat RGB multiplier across every shading variable, so e.g. a Khorne node became a single saturated red blanket. Replaced with per-curse PROFILES that tint each shading-environment variable differently — sky, sun, secondary sun, ambient, ambient top, fog, and exposure all get their own multiplier per curse. The result reads as themed atmosphere ("sunset over a burning landscape", "rotten daylight in a bog") rather than a single-color filter.

Color identity is preserved: red Khorne, green Nurgle, blue Tzeentch, pink Slaanesh, dark purple Belakor. But each curse gets accent variation (e.g. Khorne sun is warm orange against a deep red sky; Tzeentch sun has a magenta-aurora glow against cobalt sky).

### Added: Diagnostic logging on `deus_populate_graph` (cursed-mission count debugging)

User reported `cursed_mission_count = 30` produced zero visibly-cursed nodes on Olesya's map. Adding two `mod:info` lines to the existing `deus_populate_graph` hook to confirm (a) the override was read correctly and applied, and (b) how many cursed nodes vanilla's `spread_curse` actually produced in the completed graph. Both log under the `[deus_populate_graph]` prefix.

## 0.7.4-alpha (2026-05-14)

### Fixed: `Join failed - Game version mismatch` when peer has Adventure Maps injection on

Symptom: a player with `inject_adventure_maps` enabled couldn't join a friend hosting without it (or any vanilla lobby) — Steam reported "Game version mismatch" even though mod versions, network_hash, trunk_revision, and engine_revision were all identical between peers.

**Root cause.** VT2's `LobbyAux.create_network_hash` (lobby_aux.lua:26) folds `num_levels = #NetworkLookup.level_keys` into the lobby `combined_hash` that all peers compare at join time. Our `_adventure_pool.lua` registers a new level_keys entry for every injected adventure permutation (each enabled campaign / event mission × 6 themes — see `register_network_lookup_key`); without that registration the multiplayer level-load RPC fatals on a strict `__index` ("Table level_keys does not contain key"). The cost: vanilla `num_levels` ≈ 582, fully-injected ≈ 774. Peers with mismatched counts produced different `combined_hash` values and the matchmaker rejected the join.

Concretely from the failing-join log: client `combined_hash=528235b057837034 num_levels=774` vs host `combined_hash=d0ec3cbd18a2bce0 num_levels=582`, with every other hash input identical.

**Fix.** Hook `LobbyAux.create_network_hash` and temporarily nil out the injected `NetworkLookup.level_keys` entries (indices strictly greater than the vanilla count, captured once at mod load before `inject_pool` runs) for the duration of the call, then restore. Lua's `#` operator returns the contiguous-prefix length, so the vanilla hash-creation code sees vanilla `num_levels` regardless of how much we've injected. Entries are restored before the hook returns so the in-game level-load RPC, which indexes the same table, continues to work.

**Effect.**
- Peers with `inject_adventure_maps` on can join vanilla or non-matching peer lobbies. Hash matches.
- Peers hosting CW with injection on advertise a vanilla lobby hash, so vanilla peers can also join.
- Vanilla CW scenarios play correctly cross-config. The host's `LevelSettings` lookup uses string keys that exist in both configurations.

**Caveats.**
- Picking an injected adventure mission as host while a vanilla peer is in the lobby still crashes the vanilla peer: their `NetworkLookup.level_keys` doesn't contain the injected permutation key, so the level-load RPC fatals on the strict `__index`. Workaround for now: when hosting cross-config, pick a vanilla CW scenario, not an injected adventure node. A future revision could surface peer-side mod state in lobby_data to gate injected-level selection automatically.
- Other mods that legitimately register new `NetworkLookup.level_keys` entries would also be hidden by this shim. If you ever add such a mod, change `_vanilla_level_keys_count` to capture a baseline that includes those entries (or move ct's capture into a deferred init that runs after all level-mutating mods have loaded). Not a problem today — no sibling mod in the active set touches `level_keys`.

Reference: memory entry `reference_vt2_lobby_combined_hash.md` documents the full hash composition and `num_levels` source. The shim follows the pattern from `feedback_vmf_hook_safe_no_chain.md` (single mod:hook on `LobbyAux.create_network_hash` so no chain-shadow risk).

## 0.7.3-alpha (2026-05-14)

### Fixed: `[NetworkedFlowStateManager] Too many object states(512)` crash

Vanilla Fatshark bug. `NetworkedFlowStateManager.clear_object_state` (networked_flow_state_manager.lua:493) nils `_object_states[unit]` when a unit is destroyed but **never decrements `_num_states`**. The counter is monotonic — `_num_states` only grows, and the run fatals once it hits `_max_states` (512). Every destroyed unit that ever held a networked flow state permanently leaks its slot.

Hits hardest in CW runs with adventure-mission injection + curses: the `cursed_chest_objective_unit` buff is applied to every cursed-chest enemy spawn (`apply_objective_unit` in morris_buff_settings.lua:614) which spawns a `units/hub_elements/objective_unit` carrying a `chest_open_state` networked flow state. Each enemy = 1 permanently-leaked slot. Reproduced ~40 min into a Verminious Dreams khorne node after 2 Chests of Trials were activated (crash dump `console-2026-05-14-03.23.33-d86fd894-...`).

Fix: hook `NetworkedFlowStateManager.clear_object_state` to count the states being released and subtract from `_num_states` before delegating to vanilla. One-line vanilla-bug patch.

## 0.7.2-alpha (2026-05-13)

### Added: Curse sky / atmosphere tinting on adventure missions

The per-light tint from v0.6.x only colored individual point/spot lights — adventure-level skies, sun, and atmospheric fog stayed vanilla, so cursed adventure missions looked "too normal." This release adds per-frame multiplicative tinting of the live ShadingEnvironment.

Pattern lifted from Peregrinaje (bundle-unpacked from Workshop install — file 92BC0C4E7BFF8C3A.lua referenced `ShadingEnvironment.set_scalar`, `skydome_tint_color`, `sun_color`, `secondary_sun_color`, `ambient_tint`, `ambient_global_tint`, `fog_color`, `exposure`, `apply_environment_variables`). Implementation:

- `hook_safe` on `CameraManager.shading_callback` so we run AFTER vanilla `MoodHandler.apply_environment_variables` (camera_manager.lua:346) — our curse tint multiplies the post-mood color.
- Gates: only fires on injected adventure levels with a non-`wastes` node theme (khorne/nurgle/tzeentch/slaanesh/belakor).
- Variables tinted: `skydome_tint_color`, `sun_color`, `secondary_sun_color`, `ambient_tint`, `ambient_tint_top`, `fog_color`.
- Per-curse multipliers tuned to be visible without flattening the scene.
- No save/restore: Stingray re-seeds the shading_environment from the level's baked template every frame, so leaving the cursed node automatically restores vanilla atmosphere.

## 0.7.1-alpha (2026-05-13)

### Fixed: Chest of Trials no longer interactable

v0.6.28–v0.7.0 hooked `_spawn_pickup` to mutate the chest's physics actors (scene_query / collision_filter / collision_enabled) in an attempt to make altars/chests walk-through on adventure levels. Each variant broke chest interaction. Reverted the entire actor-manipulation hook.

Researched the Peregrinaje mod's source (bundle-unpacked from Workshop install): Peregrinaje does NOT touch chest collision — it relies on vanilla pickup-spawn flow with `with_physics = false`, which destroys an actor named `"pickup"` via `PickupUnitExtension.set_physics_enabled` (pickup_unit_extension.lua:125-135). That actor is only a small trigger zone though; the chest's main collision body stays. In vanilla CW the level designer places altars/chests in alcoves so they're never on the path — there is no engine mechanism that makes them walk-through on demand.

Accepting that altars/chests can block on adventure-level injections (per user direction: "give up on collisions"). The chests are now back to interacting properly.

### Fixed: Campaign potions appearing when `enable_campaign_potions` is off

Defensive cleanup at the top of `populate_pickups`: when the toggle is off, scrub `damage_boost_potion`, `speed_boost_potion`, `cooldown_reduction_potion` from `Pickups.deus_potions` every call. Guards against a mid-flight error in a previous (toggle-on) call leaving the campaign-potion clones in the table.

## 0.7.0-alpha (2026-05-13)

First experimental public release. Marks the formal opening of the mod to a broader audience after months of internal iteration. Title changed to "Tweaker: Chaos Wastes" (was "Tweaker: Chaos Wastes (WIP)"), Workshop description rewritten to cover the full feature surface, new thumbnail in place.

Headline since the last released build: the **Adventure Maps in Chaos Wastes** subsystem. Adventure missions are now injectable into the CW random map pool with full mission lifecycle (curses, boons, finale routing) intact: tomes/grims become Chests of Trials, pickups rewrite to CW types, altars seed at 5/map (1 upgrade + 1 melee swap + 1 ranged swap + 2 boon), cursed nodes carry the matching sky/lighting tint, and altars/chests use `filter_trigger` so the player walks through them.

## 0.6.33-dev (2026-05-13)

### Fixed: Event barrels spawning as potions (broke scripted events)

`_can_spawn` hook was returning true for `deus_potions`/`deus_soft_currency`/`deus_weapon_chest` on EVERY adventure spawner (except tome/grim), including **triggered event spawners** for scripted lamp_oil / explosive_barrel / training_dummy_bob spawns. `_spawn_guaranteed_pickup` iterates all pickup names asking `_can_spawn` for each, then picks randomly from candidates — so a triggered barrel-spawner could roll `healing_draught` instead of `lamp_oil` and break the scripted event.

Fix: in the `_can_spawn` adventure-fallback, also short-circuit to `false` when:
- `Unit.get_data(spawner, "guaranteed_spawn")` is truthy (book / specified spawners)
- `Unit.get_data(spawner, "triggered_spawn_id")` is a non-empty string (event-driven spawners)

CW types still flow onto generic primary spawners (the ones without any specific event tag) so coin / potion / altar counts are unaffected.

## 0.6.32-dev (2026-05-13)

### Fixed: Chest of Trials interaction broken in v0.6.28+

v0.6.28's `Actor.set_scene_query_enabled(actor, false)` made altars/chests walk-through BUT broke interaction with them. Cause: `GenericUnitInteractorExtension._find_best_interaction_unit` (interactor extension line 254) discovers interactables via `PhysicsWorld.immediate_overlap(..., "collision_filter", "filter_overlap_interaction")` which needs scene_query=true on the actor. The "proximity check" assumption in the v0.6.28 comment was wrong — interaction discovery is scene-query-driven.

Fix: revert scene_query disable. Instead, reclassify the actor's collision filter to `filter_trigger` via `Actor.set_collision_filter` — the vanilla "non-blocking interactable" filter (see `ai_utils.lua:521` for the canonical pattern). The player_mover sweep ignores `filter_trigger` actors so the player walks through; raycast overlaps still hit them so interaction works.

`set_collision_enabled(false)` is also kept as belt-and-braces but the filter change is the load-bearing piece.

## 0.6.31-dev (2026-05-13)

### Fixed: Exact cursed-mission count

Setting `cursed_mission_count` was driving `CURSES_HOT_SPOTS_MIN/MAX_COUNT` only, but vanilla `spread_curse` (deus_populate_graph.lua:681) then *spread* each cluster center to neighbouring nodes within `CURSES_HOT_SPOT_MIN_RANGE..MAX_RANGE`, so requesting N would typically yield 5–15 cursed nodes. Fix: when the override is active, also force `CURSES_HOT_SPOT_MIN_RANGE = MAX_RANGE = 0` so each cluster curses only its center node. Both ranges are saved before the override and restored in `restore_curse_count` so vanilla CW spread behaviour returns intact when the setting is back to 0.

## 0.4.1-dev (2026-05-10)

### Fixed: `<<1>>`..`<<9>>` in altar count dropdowns

The four altar-count dropdowns (Upgrade / Melee Swap / Ranged Swap / Boon Altars) showed `<<1>>` through `<<9>>` instead of plain `1`–`9`. Cause: `altar_count_options` used `text = "1"`..`"9"` as labels, expecting VMF to fall through to the literal string when no loc entry matched. VMF actually wraps missing keys in `<<>>`. Fix: added explicit `["1"]` … `["9"]` entries in `_localization.lua`. Updated the misleading comment in `_data.lua` to document the real VMF behaviour.

## 0.4.0-dev (2026-05-10)

### Added: Bomb-boon balance toggles

Four new toggles in **Modified Boons** group, sourced from a community balance thread:

- **Bomb Boon Cooldown (s)** — uniform cooldown override for the *Drop bomb on ability use* boon. Vanilla per-item cooldowns are 180s (Rally Flag), 180s (Morgrim's Bomb), 120s (Endless Bombs Potion); a single positive value here applies uniformly to all three. 0 = vanilla. Implemented by mutating `DeusPowerUpTemplates.drop_item_on_ability_use.buff_template.buffs[1].cooldown_durations` (read at proc time in `morris_buff_settings.lua:2830`). Mirrors the Khaine's Fury save-and-restore pattern; reverts on `on_disabled` and re-applies on setting change.

- **Bomb Boons Mutually Exclusive** — once any bomb boon is owned (`drop_item_on_ability_use` or `deus_grenade_multi_throw`), other bomb boons are stripped from the random pool for the rest of the run. Implemented inside the existing `generate_random_power_ups` save-and-restore filter (the third hook arg is `existing_power_ups`); piggybacks on the same removed-then-restored pool list.

- **Endless Bombs Consumes Morgrim's** — when the Endless Bombs potion is drunk, any saved Morgrim's Bomb is permanently destroyed instead of dropped on the ground. Hooks `BuffFunctionTemplates.functions.apply_pockets_full_of_bombs_buff` and calls `destroy_slot("slot_level_event")` only when the slot item is `holy_hand_grenade`; other level-event items keep vanilla drop behaviour.

- **Block Ranger Veteran from Saving Morgrim's** — RV's `bardin_ranger_passive_consumeable_dupe_grenade` (10% chance not to consume on grenade throw, applied via `not_consume_grenade` proc stat_buff) cannot fire when the thrown grenade is a Morgrim's Bomb. Hooks `ActionChargedProjectileUtility.fire_charged_projectile`; instance-level monkey-patch of the buff_extension's `apply_buffs_to_value` for the duration of the call (with `rawget`-aware restore through `__index`), gated on `projectile_context.item_name == "holy_hand_grenade"`.

## 0.3.9-dev (2026-05-09)

Version bump for batch deploy. No behaviour changes since 0.3.4-dev — the gap reflects internal version increments during cross-mod work that didn't land separate CW changes.

## 0.3.4-dev (2026-05-01)

### Fixed: Banned Weapon Traits list

The previous list had 20 entries, of which **7 were no-ops** because the names didn't match any real CW weapon trait: `increased_punch_through`, `off_balance`, `power_vs_skaven` (a property, not a trait), `resourceful_combatant`, `scrounger` (a deus weapon theme name), `shockwave` (also a theme), `swiftslaying`. The other 13 silently missed real traits like Swift Slaying, Shockwave, Off Balance, Piercing Projectiles, Resourceful Sharpshooter, etc. — so users couldn't actually ban those.

Replaced with the **31 real traits** that appear in `DeusWeapons[*].baked_trait_combinations`, dumped via the new `dump_traits` command and labeled with Fatshark's official display names + descriptions as tooltips. Banned-trait setting names now match `WeaponTraits.traits[name]` keys exactly, so the runtime check `mod:get("ban_trait_" .. trait)` actually fires.

## 0.3.3-dev (2026-05-01)

### Added: `dump_traits` command

New console command lists every weapon trait that can roll on any CW weapon (union of `DeusWeapons[*].baked_trait_combinations`), resolving each trait's `display_name` and `advanced_description` via `Localize()`. Used to gather the official Fatshark text needed to give the Banned Weapon Traits options proper labels and tooltips.

## 0.3.2-dev (2026-05-01)

### Fixed: `<<key>>` placeholders in mod options menu

40 boon-disable / starting-boon widgets referenced tooltip keys (`disable_boon_squats_tooltip`, `start_boon_squats_tooltip`, `..._deus_power_up_quest_granted_test_01_tooltip`, and all 36 `*_talent_N_M_tooltip`) that were never defined in `_localization.lua`. VMF rendered the unresolved keys as raw `<<key>>` strings on hover. Removed the broken tooltip refs from the widgets — the labels themselves were already auto-generated stubs (`"Talent 1 1"`, `"Squats"`, etc.) with no descriptive text to put in tooltips.

## 0.3.0-dev (2026-05-01)

### Fixed: Campaign potions in CW now actually spawn

The `enable_campaign_potions` toggle never produced visible results because the patch shared the campaign potion settings tables by reference. Engine-startup normalization (in `pickups.lua`) divides each entry's `spawn_weighting` by the sum of its group, so campaign-potion entries had weights ~3× the CW potions. The random sampler iterates with `pairs()` and breaks on the first cumulative weight that hits the random value (in `[0,1)`); the CW potions consistently exhausted that range first, so campaign potions never got picked. Fix: clone the entries and override their `spawn_weighting` to match the CW potion scale.

### Fixed: Boon labeled as "Reckless Swings" is actually called "Khaine's Fury"

Renamed the modified-boon toggle to "Tweak: Khaine's Fury" to match the in-game display name.

### Changed: Altar count defaults are now 0 = vanilla random

`chest_upgrade_count`, `chest_swap_melee_count`, `chest_swap_ranged_count`, and `chest_power_up_count` now default to 0 (leave vanilla distribution untouched). Range expanded from 0–8 to 0–9. Setting any of the four to a non-zero value still replaces the entire chest distribution; types still at 0 produce no altars of that type.

## 0.2.5-dev (2026-04-28)

### Added: Disabled Boons

All 172 boons can now be individually disabled from appearing at shrines, chests, altars, and Belakor's Temple. Boons are organized into 6 sub-groups: Properties, Talents, Skulls & Sets, Combat, Healing & Sustain, Utility & Team.

### Added: Starting Boons

All 172 boons can be toggled on as starting boons granted at the beginning of a Chaos Wastes run. Uses the same 6 sub-groups. Starting boons bypass the disabled-boons list and are granted to all players based on host settings.

### Added: Modified Boons

New "Modified Boons" section for per-boon gameplay tweaks. First entry: **Reckless Swings** — reduces self-damage from 3 to 1 per hit and lowers the health threshold from 50% to 25%, letting the boon stay active longer. Tooltip updates dynamically when the tweak is enabled.

### Added: Banned Weapon Traits

20 Chaos Wastes weapon traits can be individually banned from appearing on weapon upgrades.

### Fixed: Boon localization

Boon names in settings UI now display readable names instead of raw internal keys (e.g. "Attack Speed" instead of `<attack_speed>`). Localization is generated at mod registration time from the static boon key list, then upgraded to actual game display names on first Chaos Wastes entry.

### Changed: Removed redundant settings wrapper

Settings are no longer nested inside a redundant "Chaos Wastes" collapsible group.

## 0.2.0-dev (2026-04-24)

### Added: Version logging

Mod now logs `Chaos Wastes Tweaker v<version> loaded` on init so the running version can be verified in the console log.
