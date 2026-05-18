# Chaos Wastes Tweaker Changelog

## 0.7.58-alpha (2026-05-18)

### Fixed: Belakor altar spawn fatals `Unit not found #ID[ee6ba7f91c666e61]` on adventure-injected levels

When `force_belakor` was on and the engine rolled a Belakor altar onto an adventure-injected mission's first remaining book spot, `World.spawn_unit("units/props/blk/blk_locus_01", ...)` hit the C-level assert at `c_api_world.cpp:67` because the unit wasn't in any loaded resource package. The locus prop ships in `resource_packages/levels/dlcs/morris/belakor_common`, which vanilla CW belakor-themed levels load via `level_settings_morris.lua`'s `theme_packages_lookup.belakor`. Our adventure-injection clones the adventure level's `packages` table and adds `morris_ingame` + the deus chest unit + DLC career packages — but not the belakor_common package, so the locus unit was unresolvable.

`build_permutation_packages` (`_adventure_pool.lua`) now appends `resource_packages/levels/dlcs/morris/belakor_common` to every injected permutation regardless of theme. `force_belakor` can ignite a Belakor altar on any theme via `_spawn_guaranteed_pickup`, so the package must be available unconditionally. Diagnosed via `crashify://142f40f3-d01d-4811-bd8b-e97272b8afcb` (entered `levels/dlcs/scorpion/alleys_heavens` aka Old Haunts as a Belakor pilgrimage); hash decoded by brute-forcing candidate unit paths through the bundle unpacker.

The `DeusRunController.can_spawn_belakor_locus` permit added in v0.7.51 + the `_spawn_guaranteed_pickup` slot grant added in v0.7.55 stay as-is — they correctly OPEN the spawn gate; v0.7.58 just ensures the asset exists when the spawn actually runs.

## 0.7.57-alpha (2026-05-16)

### Fixed: Manann's Tempest cooldown hook targeted the wrong table → VMF logged "trying to hook function or method that doesn't exist"

The v0.7.48 cooldown hook for `chain_lightning` targeted `BuffFunctionTemplates.functions`, but `chain_lightning` actually lives in the GLOBAL `ProcFunctions` table:

- morris_buff_settings.lua:131-2144 is `dlc_settings.morris.buff_function_templates` (the apply-callback category — that's where `apply_pockets_full_of_bombs_buff` lives, and why our `endless_bombs_consumes_morgrim` hook on the same target works).
- morris_buff_settings.lua:2145+ is `dlc_settings.morris.proc_functions` (event-driven procs — `chain_lightning` is at line 2563 in this block).
- At runtime BuffExtension consults `ProcFunctions[buff_func_name]` (buff_extension.lua:1350) — `BuffFunctionTemplates.functions.chain_lightning` is nil.

VMF logged the registration failure but kept loading (unlike the v0.7.53 crash that killed the entire mod), so this was a soft fail: Manann's Tempest cooldown gating just never engaged. Now hooks `ProcFunctions.chain_lightning` directly — both the boon variant (unconditional 8s cooldown) and the trait variant (gated by `tweak_manann_tempest_cooldown`) work as designed.

## 0.7.56-alpha (2026-05-16)

### Fixed: module-load crash since v0.7.53 silently disabled most of the mod

`v0.7.53` consolidated `_make_meta_apply` + `_make_meta_granted` into a single `_make_meta_proc` factory, but the special-cased `ct_meta_movespeed` registration at line ~3460 (separate from the loop because movespeed uses `apply_movement_buff` instead of stat_buff) was missed in the rename. At mod load, Lua raised `attempt to call global '_make_meta_apply' (a nil value)` — VMF aborted `mod_script` initialization at that point, so EVERY hook, registration, and binding after line 3463 silently never ran. That stripped:

- The four trait-as-boon registrations (Vaul's Anvil / Manann's Tempest / Taal's Twinned Arrow / Asuryan's Wrath boon variants)
- `ct_meta_movespeed` (Boon Bound Steps)
- `ct_kill_heal` (Khaine's Communion)
- The Home Brewer +50% potion-potency hook
- The Manann's Tempest 8s cooldown hook (the entire v0.7.48 feature)
- `endless_bombs_consumes_morgrim`
- The Ranger Vet save-grenade-block hook
- The defeat-recovery handler
- `mod.on_setting_changed` / `mod.on_disabled` (live updates and cleanup gone)
- **The host-side `sync_host_dependent_state` assignment** — meaning settings broadcast was partially broken too

Fix: switch `ct_meta_movespeed` to use `_make_meta_proc(stack_name)` (same as the loop-registered meta boons). Also renamed the inline sub-buff's `name` field from `"ct_meta_movespeed_stack"` to `"ct_meta_movespeed_stack_1"` so the proc's `num_buff_stacks(stack_name .. "_1")` delta-check finds the existing stacks (otherwise it would over-stack each grant, same shape as the Bug 2 from v0.7.53 but for movespeed).

If you've been on any v0.7.53–v0.7.55 build, an unknown swath of features were silently dead. v0.7.56 actually wires them all up.

## 0.7.55-alpha (2026-05-16)

### Changed: Belakor altar now spawns at a book pedestal alongside Chests of Trials on adventure-injected missions

Previously (v0.7.51) the altar was injected via `populate_pickups.primary.deus_02 = 1`, which placed it in a random ammo/healing/grenades primary spot. User asked for it to share the 5 book-spot budget instead — 3 tomes + 2 grimoires on every adventure level. The first `cursed_chest_count` book spots become Chests of Trials (default 1); the next book spot becomes the Belakor altar when `force_belakor` is on (one per mission). Remaining book spots stay hidden as before. Removed the populate_pickups inject and the `_can_spawn` allow-list for `deus_02` — both are unnecessary now that `_spawn_pickup` is invoked directly from the tome/grim spawner hook. The `DeusRunController.can_spawn_belakor_locus` override is still required because `_spawn_pickup` calls `pickup_settings.can_spawn_func`, which routes to `can_spawn_belakor_locus`.

### Changed: sync-all-settings by default — drop hand-maintained `SYNCED_SETTING_NAMES`

After repeated bugs caused by forgetting to add a setting to the synced-broadcast list (most recently: `disable_curse_*` helper bypassed the sync, `finale_dominant_god` / `force_belakor` weren't reaching clients, the `coin_multiplier` / `shrine_boon_count` / `chest_boon_count` / `bomb_boon_exclusive` / `disable_boon_*` / `ban_trait_*` / `tweak_home_brewer_potency` / `endless_bombs_consumes_morgrim` / `rv_no_save_morgrim` toggles all silently diverged on clients), the sync model is now opt-out instead of opt-in.

- `SYNCED_SETTING_NAMES` is built at module load by walking the data file's widget tree (`mod:dofile` + recursive visit of every leaf `setting_id`). Every setting the user can configure gets broadcast from the host to clients automatically.
- A small explicit `PER_PEER_SETTING_NAMES` excludes the three settings that are deliberately each-peer-local: `tweak_defeat_recovery` (per-peer locality is part of the design), `enable_campaign_potions` (server-driven spawn ignores client-side table mutation), `inject_adventure_maps` (lobby-hash-affecting, host/client must match at lobby-join time anyway).
- All the previously-direct `mod:get` callsites that should be host-authoritative now route through `effective_setting`: `coin_multiplier` (coin pickups now use host's multiplier), `shrine_boon_count` / `chest_boon_count` (boon picker counts match host), `bomb_boon_exclusive` (pool filter applies uniformly), `disable_boon_*` (boon pool filter), `ban_trait_*` (weapon trait filter), `tweak_home_brewer_potency` (potion potency scaling), `endless_bombs_consumes_morgrim` (Morgrim destroy-vs-drop), `rv_no_save_morgrim` (Ranger Vet grenade-save proc).
- `effective_setting` is now forward-declared near the top of the file so the early-running `on_soft_currency_picked_up` hook (line ~140) can capture the local slot at closure-creation time — without the forward-declare, that closure would have bound to a nil global.

Net effect: every UI setting in the mod menu now behaves host-authoritatively by default. Adding a new setting requires no bookkeeping — the broadcast picks it up automatically just by living in the data file.

## 0.7.54-alpha (2026-05-16)

### Fixed: `disable_curse_*` toggles weren't host-synced at the call site — client saw different curse text than host

`is_curse_disabled` read `mod:get("disable_curse_<name>")` directly instead of routing through `effective_setting`. Even though all 14 `disable_curse_*` keys ARE in `SYNCED_SETTING_NAMES` (so the host broadcasts them), this helper bypassed the sync and read each peer's local toggle. The two consumers (`MutatorHandler._activate_mutator`, `DeusMechanism.get_current_node_curse`) plus the `_transition_next_node` / `start_next_round` save-restore around `node.curse` therefore made decisions based on whoever-was-asking's settings, not the host's.

Symptom: gameplay-side mutator state could diverge between peers, and (the visible one) Holseher's map / mission-tooltip curse text on a client read the client's local toggle — host could see "no curse" while client saw the curse name, or vice versa, even though the actual mutator was the host's.

Fix: forward-declare `is_curse_disabled` near the top of the file (so existing call sites still bind correctly), assign the body just below `effective_setting`, and route the lookup through `effective_setting`.

## 0.7.53-alpha (2026-05-16)

### Fixed: Quiver Cascade (`ct_meta_ammo`, +5% total ammo per boon) did nothing in-game — two bugs

**Bug 1 (stale ammo cache).** `GenericAmmoUserExtension._apply_buffs` queries `apply_buffs_to_value(_original_max_ammo, "total_ammo")` once at AmmoExtension init and caches the result as `_max_ammo`. Adding new `total_ammo` stat_buffs after that point updates BuffExtension but doesn't bust the AmmoExtension cache, so the +5%-per-boon never showed up even when stacks were present. Fix: `apply_buff_func = "refresh_ranged_slot_buffs"` on the stack sub-buff (vanilla's canonical "I changed an ammo stat, recompute max_ammo" hook, used by Markus huntsman's passive and others; idempotent under repeated calls). `register_meta_boon` now propagates `apply_buff_func` from the spec into the sub-buff entry.

**Bug 2 (quadratic stack growth).** The `_make_meta_granted` proc queried `num_buff_stacks(stack_name)` to decide how many delta-stacks to add. But the actual stored key is `sub_buff_template.name`, which the factory builds as `stack_name .. "_" .. i` — so the query returned 0 every time and the granted proc re-added the full current boon count on every subsequent boon grant (triangular sum: after N additional boons the player had N(N+1)/2 stacks, not N). With Bug 1 masking everything visually, this went unnoticed.

Fix: consolidated apply + granted into a single `_make_meta_proc` that queries `num_buff_stacks(stack_name .. "_1")` (the first sub-buff's actual name) and adds only the delta. Same body for both procs so the result is idempotent regardless of fire order — vanilla `on_boon_granted` fires before the new boon's own apply, so the apply path handles the initial stack-up and granted handles incremental boons.

Other meta boons (stagger / crit / cooldown / health) ran the same buggy granted-proc, but their stat_buffs are queried per-use (not cached like total_ammo), so Bug 1 didn't apply and Bug 2 made them OVER-buffed rather than silently inert. Both are now fixed for every meta boon — expect previously over-buffed runs to feel "weaker" but correct.

### Fixed: finale_dominant_god override didn't reach clients — same bug shape as the v0.7.49 Belakor sync fix

The previous `_setup_run` hook flipped `dominant_god` only in host's local run state. `game_round_ended` (deus_mechanism.lua:551-619) reads `self._vote_data.dominant_god` into a local at the top and uses that single value for BOTH `_setup_run` AND `send_rpc_clients("rpc_deus_setup_run", ..., dominant_god_id, ...)`. The hook never reached the RPC payload, so clients populated their graph with the unmodified god.

Fix: hook `DeusMechanism.game_round_ended` and pre-mutate `self._vote_data.dominant_god` before vanilla runs; restore after. The mutation is host-only, gated on `reason == "start_game"`, and restores even if vanilla errors (pcall + rethrow). Vote_data persists on `self` until next mission-start, so restore-on-return is mandatory.

The `_setup_run` finale_dominant_god branch is removed since it was always redundant for the host and broken for clients.

## 0.7.51-alpha (2026-05-16)

### Added: Belakor altar (`deus_02`) spawns on adventure-injected campaign levels when host has "Always Include Belakor's Temple" on

Three coordinated changes route an altar into each adventure-injected map:

- `populate_pickups` injects `pickup_settings.primary.deus_02 = 1` (with proper save/restore so toggling the setting off cleanly reverts), gated on `on_injected_adventure_level() and effective_setting("force_belakor")`.
- `PickupSystem._can_spawn` adds `deus_02` to the allow-list for adventure-injected levels. The populate_pickups gate is the only place a request gets generated, so vanilla / non-belakor runs are unaffected.
- `DeusRunController.can_spawn_belakor_locus` returns true on adventure-injected levels when force_belakor is on. The vanilla gate rejects every non-belakor-themed node (campaign themes don't qualify), so without this the altar would still be vetoed at spawn time even after populate_pickups requested one.

`force_belakor` is now host-authoritative — added to the synced settings broadcast so clients use the host's value consistently across all three gates.

## 0.7.50-alpha (2026-05-16)

### Fixed: Moot Milk (Hangover Brew) alt rework slowed the player to 25% instead of +25%

The reworked Moot Milk's movement-speed sub-buff had `multiplier = 0.25` with `apply_buff_func = "apply_movement_buff"`. That function does `move_speed *= multiplier`, so 0.25 capped the player at 25% of base speed (a -75% slow) for the entire potion duration. Vanilla speed_boost_potion uses 1.5 for +50%; the intended +25% needs 1.25. Code comments / changelog have always advertised this as +25% — the value was just wrong since the rework shipped. Decanter-extended (`_increased`) variant inherits from the same builder, so it's fixed too.

## 0.7.49-alpha (2026-05-16)

### Fixed: clients couldn't see the Belakor curse on Holseher's map when host had "Always Include Belakor's Temple" on

Previously the `force_belakor` override was applied inside `DeusMechanism._setup_run`. That works for the host's own run state, but the upstream caller (`game_round_ended`) computes `with_belakor` BEFORE calling `_setup_run`, then re-uses that same outer-scope variable when it broadcasts `rpc_deus_setup_run` to clients. The hook never reached the RPC payload, so clients ran graph generation with `with_belakor=false` and rolled no Belakor nodes / no Belakor curse spread.

Fix: hook the upstream `BackendInterfaceDeusPlayFab.deus_journey_with_belakor` so the override happens at the source. Now both `_setup_run` and the RPC use the same modified value, and clients see the Belakor curse propagated through the graph.

Known related bug (NOT fixed in this version): `finale_dominant_god` has the same shape — the `_setup_run` hook flips the host's local `dominant_god` but the RPC keeps the original. Clients on a `finale_dominant_god`-overridden run see vanilla god distribution on their map. File a follow-up if this matters.

## 0.7.48-alpha (2026-05-16)

### Added: Manann's Tempest — 8s per-source cooldown

Wraps `BuffFunctionTemplates.functions.chain_lightning` to enforce a per-owner cooldown:

- **Boon variant** (the Unique-rarity Manann's Tempest boon, when its toggle is on) — always rate-limited to 1 chain per 8 seconds. No new toggle; the boon now ships with this cap baked in.
- **Trait variant** (the vanilla `deus_crit_chain_lightning` weapon trait) — new toggle `tweak_manann_tempest_cooldown` under Reworks > Reworks: Boons. Off (default) = vanilla (no cooldown, fires on every crit). On = 8s cooldown that mirrors the boon.

Boon and trait cooldowns are independent buckets per `owner_unit`, so running both gives you one chain per 8s from each side (matches the existing stacking design). The cooldown gate mirrors the proc's own ALIVE / first_hit / is_critical_strike check so it only consumes on procs that would actually have fired. Trait toggle is host-authoritative via the existing settings sync.

## 0.7.47-alpha (2026-05-16)

### Added: Rework — Killer in the Shadows potion lasts 2x as long

New toggle in Reworks > Reworks: Potions. Doubles the invisibility potion's duration: base 5s → 10s, increased 15s → 30s (Decanter then stacks on the increased variant the usual 50%, giving 15s/45s). Same `BuffTemplates` save-and-restore pattern as the Poison Proof duration rework — mutates `BuffTemplates.killer_in_the_shadows_potion.buffs[1].duration` + `_increased` at apply, restores on revert. Synced via the host-authoritative settings broadcast.

## 0.7.28b → 0.7.40-alpha (2026-05-15) — consolidated session log

Twelve versions in one session. Listed chronologically by version.

### 0.7.28b — Rework: Shard Strike duration nerf (configurable)
Toggle in Reworks > Reworks: Boons. Slider 1–16s controls the duration of Shard Strike's damaging stagger aura (vanilla 16s, overtuned at top tier). Mutates `WeaponTraits.buff_templates.armor_breaker.buffs[1].duration` + the global `BuffTemplates` mirror; save-and-restore so toggling off restores vanilla.

### 0.7.29 — Activate Dormant Boons feature
9 dormant boons (defined in source but never registered in `DeusPowerUpRarityPool`) get individual activation toggles. When enabled, the boon is injected into the rarity pool and all derived runtime tables (`DeusPowerUps`, `DeusPowerUpsArray`, `DeusPowerUpsArrayByRarity`, `DeusPowerUpsLookup`, `DeusPowerUpBuffTemplates`) using the same construction pattern as vanilla's registration loop at `deus_power_up_settings.lua:7121-7176`. Includes: Mathlann's Bounty, Bögenauer's Prosperity, Nethu's Relentlessness, Grungni's Gift, Hashut's Greeting, timed-block free shot, Smednir's Transmutation, Chotec's Touch, Squats. Dormants appear in `starting_boons` with `(Dormant)` suffix; pulled from `disable_boons` since they only roll when activated.

### 0.7.30 — 4 new Mod Boons (per-boon scaling)
Modeled on vanilla's `boon_meta_01` (Lileath's Favour). Each scales different stats per total active boon count:
- **Reactive Bulwark** (`ct_meta_stagger`) — +1% stagger power + 1% melee cleave per boon
- **Crit Cascade** (`ct_meta_crit`) — +1% crit chance + 5% crit power per boon
- **Vitality Cascade** (`ct_meta_health`) — +1% max HP + 1% healing received per boon
- **Ability Cascade** (`ct_meta_cooldown`) — +2% cooldown regen per boon

New "Mod Boons" boon-tree category. Localize hook routes the display name and description keys.

### 0.7.31 — Home Brewer +50% potency for reworked potions
When the player holds Home Brewer (the `not_consume_potion` perk), the Moot Milk rework's numerical multipliers scale by 1.5x for that drink. Implementation: hook `BuffExtension.add_buff`, save the template's multiplier/bonus fields, scale, call vanilla add, restore. Multiplayer-safe via per-peer perk check.

### 0.7.32 — New Mod Boon: Khaine's Communion
Exotic-rarity mod boon: heal 1 permanent HP on every enemy kill. Server-authoritative proc with `authority = "server"`; `DamageUtils.heal_network` with `heal_from_proc` heal type. Catalogued under Defensive > Health by effect, prefixed `(Mod Boon)` in display name.

### 0.7.33 — Addaioth's Splendour description fix
Vanilla in-game text said "Every 30 seconds, ranged Critical Hits explode for 10% of their Damage" but the actual implementation uses cooldown_duration = 10 and damage = 30% (vanilla swapped the values positionally when filling description_values). Static loc override via the existing `_G.Localize` hook returns the corrected string.

### 0.7.34 — Trait-as-Boon: 4 traits as opt-in Unique-rarity boons
Per user request, four weapon traits get optional boon variants (each behind its own toggle, default off):
- **Vaul's Anvil** — naturally non-stacks with the trait (binary perk)
- **Manann's Tempest** — stacks with the trait (each fires its own chain lightning per crit)
- **Taal's Twinned Arrow** — stacks (+2 projectiles if both held)
- **Asuryan's Wrath** — melee-only via the existing proc filter; stacks with the trait (~75% effective proc chance with both)

`register_trait_boon` clones the source trait's buff template, registers a new power-up template, and injects via `inject_dormant_boon` at Unique rarity.

### 0.7.35 — New Mod Boon: Wind Cascade
Exotic-rarity mod boon: +1% movement speed per active boon. Uses `apply_movement_buff` (the only function that actually moves the player's speed needle in vanilla — plain `stat_buff = "movement_speed"` isn't read by anything). Each stack compounds via `1.01^N`; at 1% per stack the compounding diff is tiny (10 stacks = +10.5% vs +10% additive).

### 0.7.36 — Rework: Anath Raema's Swiftness permanent
Swaps the trait's on-ammo-pickup-temporary `+50%` reload speed (10s window) for a permanent passive reload speed while the weapon (with the trait) is wielded. Mutates both `WeaponTraits.buff_templates.deus_ammo_pickup_reload_speed` AND `BuffTemplates.deus_ammo_pickup_reload_speed` with save-and-restore.

### 0.7.37 — Crash fix: dormant boons at "common" rarity
**Crash:** `deus_power_up_utils.lua:208: attempt to index a nil value`. **Root cause:** `DeusPowerUpRarities` is `{ event, rare, exotic, unique }` — only 4 valid boon rarities. "common" and "plentiful" are weapon-drop rarities, NOT boon rarities. I'd injected `squats` and `deus_larger_clip` at "common" → `existing_power_ups_lut["common"]` was nil → crash on next shrine after rolling either boon. **Fix:** moved both to "rare". Memory saved: `reference_vt2_deus_power_up_rarities.md`.

### 0.7.38 — Crash fix: NetworkLookup.buff_templates missing entries
**Crash:** `network_lookup.lua:2514: [NetworkLookup.lua] Table buff_templates does not contain key: power_up_deus_timed_block_free_shot_exotic`. **Root cause:** my `inject_dormant_boon` was registering the buff in `DeusPowerUpBuffTemplates` and `BuffTemplates` but NOT in `NetworkLookup.buff_templates`. NetworkLookup has a metatable that throws on unknown keys. **Fix:** new `register_buff_in_network_lookup(buff_name)` helper called for every injected buff.

### 0.7.39 — Rework: Defeat Recovery (soft wipe rescue)
When the team would wipe and the toggle is on: each peer's coins are zeroed, each peer loses 5 random boons, host force-respawns dead/disabled players. Mission continues from the wipe point (NOT a full level reload — engine doesn't expose a safe mid-run reload path). Fires once per level via `_defeat_recovery_triggered_this_round` flag; resets on `_transition_next_node`.

### 0.7.40 — Crash fix: NetworkLookup.deus_power_up_templates missing entries
**Crash:** `network_lookup.lua:2514: [NetworkLookup.lua] Table deus_power_up_templates does not contain key: ct_boon_asuryan_wrath`. **Root cause:** vanilla has TWO separate NetworkLookup tables for boons — `buff_templates` (fixed v0.7.38) and `deus_power_up_templates`. The latter is used for power-up selection RPCs (chest pick, boon offer, grant). My injected boon names weren't there. Triggered when picking ANY boon at a chest while having an unregistered injected boon as a current power-up — the chest's add-and-resync re-serialized the full power-up list, hit the unregistered name, errored. **Fix:** new `register_power_up_in_network_lookup` helper called at the top of `inject_dormant_boon` for every injected boon (dormants, meta boons, ct_kill_heal, trait-as-boon variants).

## 0.7.28a-alpha (2026-05-15)

### Added: Rework — Trait Tier by Rarity

New toggle in `Reworks` group. When on, every weapon roll and altar upgrade picks a trait combo whose ALL traits are eligible for the rolled rarity (per the user-confirmed tier table walked 2026-05-15; see `TRAITS_REFERENCE.md` for the full per-trait assignment).

**Tier assignments** (34 traits total):
- **T1 Common** (9): Off Balance, Resourceful Combatant, Heroic Intervention, Parry, Resourceful Sharpshooter, Inspirational Shot, Rhya's Thorns, Anath Raema's Swiftness, Myrmidia's Great Leveller
- **T2 Rare** (9 + 2 overlap): Regrowth, Barrage, Hunter, Thermal Equalizer, Heat Sink, Opportunist, Bloodthirst, Deadeye, Follow Up + (Scrounger, Conservative Shooter)
- **T3 Exotic** (4 + 6 overlap): Divine Shield, Shockwave, Huanchi's Fangs, Swift Slaying + (Scrounger, Conservative Shooter, Anatha Raema's Talons, Vaul's Tempo, Asuryan's Wrath, Addaioth's Splendour)
- **T4 Unique** (6 + 4 overlap): Shard Strike, Asaph's Endless Quiver, Quetzl's Repulsion, Manann's Tempest, Taal's Twinned Arrow, Vaul's Anvil + (Anatha Raema's Talons, Vaul's Tempo, Asuryan's Wrath, Addaioth's Splendour)

**Implementation** (`chaos_wastes_tweaker.lua`):
- `TRAIT_RARITY_POOL` table maps each trait → set of allowed rarity strings (`{ common = true, rare = true, ... }`)
- `get_tier_filtered_combos(item_key, rarity)` filters the weapon's `baked_trait_combinations` to combos whose all traits are eligible for the rolled rarity
- `override_traits_in_result(result, rarity)` overwrites `result.traits` with a random tier-eligible pick
- Extended the existing trait-filter hooks (`generate_weapon`, `generate_weapon_for_slot`, `upgrade_item`) to also post-process via `override_traits_in_result`, and added a new hook on `generate_item_from_item_key`

**Side effects of the toggle:**
1. **Traits now roll at ALL rarities** — vanilla `deus_weapon_generation.lua:166-169` only rolls traits at Exotic/Unique. Our override doesn't rely on the vanilla rarity gate (we filter the original `baked_trait_combinations` ourselves), so Common and Rare weapons get traits too. This addresses the user's earlier "every upgrade should offer a trait" wish — every upgrade now does, because every rarity has a pool.
2. **Upgrades effectively reroll the trait** — each upgrade re-picks from the new rarity's pool, so the trait changes on every upgrade. Fulfills the "guaranteed reroll on upgrade" sub-toggle request from the trait walk.

**No-op cases (preserves vanilla):**
- Toggle off → no behavior change
- Weapon has no tier-eligible combos at the rolled rarity → vanilla result kept (probably empty `traits`, same as before)

### Deferred to v0.7.28b
- "Rework: Shard Strike duration" (nerf the 16s damaging aura — configurable)

## 0.7.27a-alpha (2026-05-15)

### Disambiguating prefixes on every boon menu label

Long dropdowns in the disable/start trees were ambiguous — you couldn't tell at a glance whether a given checkbox was a disable toggle or a start-boon toggle, especially after scrolling past the parent group header. Every item and group title now carries a path-aware prefix:

| Widget type | Disable side | Start side |
|---|---|---|
| Item (e.g., Attack Speed) | `Disable Boon: Attack Speed` | `Starting Boon: Attack Speed` |
| Group (e.g., Properties) | `Disable Boons: Properties` | `Starting Boons: Properties` |

Bulk regex transformation applied via PowerShell on `chaos_wastes_tweaker_localization.lua`:

- 172 item labels prefixed on each side (344 total item transformations)
- 10 group titles prefixed on each side (20 total group transformations)
- Tooltips left untouched (`*_tooltip` keys correctly excluded via negative lookbehind)

No tree-structure changes in this phase. v0.7.27b will rebuild the 10-group structure into the new 21-category structure documented in `BOON_CATEGORIZATION_DRAFT.md`.

Backup of original localization preserved at `chaos_wastes_tweaker_localization.lua.v0726.bak` for quick rollback if needed.

## 0.7.26-alpha (2026-05-15)

### Renamed "Modified Boons" group to "Reworks"

Broadens the umbrella to include potion reworks (and anything else we add later that mutates vanilla mechanics). Existing settings (Khaine's Fury tweak, Movement Speed boon tweak, bomb boon cooldown, Morgrim's toggles) are unchanged — only the group label and `setting_id` are renamed (`modified_boons_group` → `reworks_group`). Player-facing settings persist correctly because their own setting_ids are unchanged; VMF keys user values by individual `setting_id`, not by group path.

### Added: Tweak — Poison Proof potion lasts 4 minutes

Doubles the Poison Proof (gas/poison immunity) potion's duration from 120s to 240s. With Decanter, the `_increased` variant extends from 240s → 360s (still +50% over the new base). Implementation mutates `BuffTemplates.poison_proof_potion.buffs[1].duration` and the `_increased` sibling directly at mod load; vanilla's `action_potion.lua:68` resolution picks up `_increased` when `buff_perks.potion_duration` is held, so Decanter composition is automatic.

### Added: Tweak — Hangover Brew alternative effect

Replaces Hangover Brew's (`moot_milk_potion`) vanilla dodge-distance/dodge-speed buff with a different effect package:

- +25% movement speed (apply_movement_buff on `move_speed`)
- Unlimited dodges (`buff_perks.infinite_dodge`)
- +40% stamina regen (`stat_buff = "fatigue_regen"`)
- 60-second duration (90 seconds with Decanter, via `_increased` variant)

The visual `screenspace_drink` activation/loop effects are kept so it still feels like a potion. Implementation replaces `BuffTemplates.moot_milk_potion.buffs` with a 4-buff array (FX + MS + infinite dodge + stamina regen) at mod load; mirrors for `moot_milk_potion_increased`. Save-and-restore pattern matches the other tweaks so toggling off restores vanilla.

### Known limitation: Home Brewer composition deferred to v0.7.27

User asked for Home Brewer to provide a +50% potency boost on top of the rework. Home Brewer in vanilla is `not_consume_potion` (chance to refund the potion), not a potency boon — so the tweak would need:

1. New `<potion>_potion_brewed` and `<potion>_potion_brewed_increased` variants registered in `BuffTemplates`
2. Each variant added to `NetworkLookup.buff_templates` (else RPCs in `action_potion.lua:74` fail)
3. A hook on `ActionPotion:client_owner_buff_function` (or similar) to swap to `_brewed*` when `not_consume_potion` perk is held
4. Numeric scaling at variant-build time (multipliers × 1.5)

That's a 1-2 hour effort with its own test cycle. Splitting it out keeps v0.7.26 small and verifiable.

## 0.7.25-alpha (2026-05-15)

### Boon menu re-categorization (round 2 of 2): Ability Cooldown + Orbs groups

Per user verdict, boons whose primary benefit is ability cooldown reduction now live in their own "Ability Cooldown" group, and orb-like boons (which would otherwise be lumped in with the upcoming Vermintide Skulls event content) get their own "Orbs" group. The "Skulls" group is reserved exclusively for Vermintide Skulls event boons going forward.

**New group: "Ability Cooldown"** (6 boons) — moved out of Properties / Utility & Team:

- From Properties: `ability_cooldown_reduction`
- From Utility & Team: `cooldown_on_friendly_ability`, `deus_cooldown_reg_not_hit`, `deus_cooldown_regen`, `deus_skill_on_special_kill`, `friendly_cooldown_on_ability`

**New group: "Orbs"** (5 boons) — moved out of Combat / Defense / Healing / Utility:

- From Combat: `focused_accuracy`, `static_charge`
- From Defense, Damage Reduction & Parry: `protection_orbs`
- From Healing, THP & Health Gain: `health_orbs`
- From Utility & Team: `sharing_is_caring`

Source groups (Properties, Combat, Defense/DR/Parry, Healing/THP, Utility & Team) lose those entries respectively. Both the `disabled_boons_group` and `starting_boons_group` mirror trees are updated in lockstep, and `recursive_sort` auto-alphabetizes the four new sub-groups by display name.

## 0.7.24-alpha (2026-05-14)

### Fixed: Khaine's Fury (`tweak_reckless_swings`) — damage tweak silently failed

User reported the Khaine's Fury softening tweak didn't actually soften the damage even with the toggle on. Root cause: the apply/revert functions were mutating `DeusPowerUpBuffTemplates.deus_reckless_swings_buff.buffs[1].damage_to_deal` — but the runtime buff system reads from the global `BuffTemplates` table, which received COPIED values via `DLCUtils.merge` at game boot (`buff_templates.lua:9532`). Mutating the source `DeusPowerUpBuffTemplates` had zero effect on what the proc function `deus_reckless_swings_buff_on_hit` actually read at hit time (`template.damage_to_deal` still 3).

Fix: mutate `BuffTemplates.deus_reckless_swings_buff.buffs[1].damage_to_deal` directly instead of the source `DeusPowerUpBuffTemplates`. The outer `health_threshold` tweak via `DeusPowerUpTemplates` was already correct (the apply path at `deus_power_up_utils.lua:250` reads that table directly), so it kept working — only the per-hit damage was uncorked.

Effect: with the toggle on, melee hits now deal 1 self-damage instead of 3, matching the displayed tooltip text. Host-side mutation suffices because the proc function is `is_server()` gated and damage is networked via `add_damage_network`.

## 0.7.23-alpha (2026-05-14)

### Diagnostic: verbose logging on chest-of-trials revive hook

User reports `respawn_on_chest_complete` isn't working. Setting was confirmed `true` in user_settings, hook registered correctly in last session's log, but no observable revives. Added `mod:info` lines to `DeusCursedChestExtension._set_state` hook so the next log shows:

- Whether `_set_state` fires at all, and which state value (verifies the hook isn't being shadowed and state OPEN is being reached).
- Setting value, `is_server` flag (verifies the host-only + setting-on gates pass).
- Per-slot dump at chest-open time: peer_id, `health_state`, `unit_alive`, `is_knocked_down`, `is_disabled_by_pact_sworn`.
- Whether `StatusUtils.set_revived_network` was called (knocked-down branch).
- Whether `pending_chest_respawn[peer]` was set (dead branch).
- Whether `game_mode:force_respawn_dead_players()` was called.

If chest-revive is working but not noticed (host-only hook + no dead teammates during testing), the log will show empty branches. If the hook isn't firing at all, that narrows the diagnosis to either wrong `state` value, missed `is_server` gate (testing as client), or shadowed hook. Strip the logging once root cause is fixed.

## 0.7.22-alpha (2026-05-14)

### Boon menu re-categorization (round 1 of 2)

Started reorganizing the 172-boon disable / starting-boon menus into more cohesive categories. Categories 1 and 2 done this round; remaining 5 groups TBD.

**New group: "Defense, Damage Reduction & Parry"** — aggregates 23 boons that were previously scattered across Properties / Combat / Healing & Sustain:

- From Properties: `block_cost`, `protection_aoe`, `protection_chaos`, `protection_skaven`, `push_block_arc`, `stamina`
- From Combat: `barkskin`, `deus_block_procs_parry`, `deus_damage_reduction_on_incapacitated`, `deus_parry_damage_immune`, `deus_push_cost_reduction`, `deus_standing_still_damage_reduction`, `deus_timed_block_free_shot`, `explosive_pushes_on_damage_taken`, `missing_health_power_up`, `pent_up_anger`, `skill_by_block`, `speed_over_stamina`, `static_blade`, `thorn_skin`
- From Healing & Sustain: `deus_knockdown_damage_immunity_aura`, `hidden_escape`, `protection_orbs`

**Renamed: "Healing & Sustain" → "Healing, THP & Health Gain"** with reshuffled contents:

- Gained: `health` (from Properties), `resolve` (from Combat), `deus_coin_pickup_regen` (from Utility & Team), `boon_supportbomb_healing_01` (from Bombs)
- Lost: the three boons moved to Defense/DR/Parry above

**Other moves (per user verdicts):**

- `last_player_standing_power_reg`: Combat → Utility & Team (user verdict — utility)
- `deus_push_charge`, `deus_push_increased_cleave`: stayed in Combat (user verdict — offense, even though they're push-related)

The `recursive_sort` helper now also auto-sorts the new `disable_boon_defense_and_dr_group` and `start_boon_defense_and_dr_group` alphabetically by display name. Both `disabled_boons_group` and `starting_boons_group` mirror trees have been updated in lockstep.

Categories still pending (TBD next session): Combat (further split into damage / crit / ranged / etc.?), Utility & Team, Bombs, Skulls & Sets, Talents, Properties. User to provide further verdicts.

## 0.7.21-alpha (2026-05-14)

### Added: Host→client settings sync (clients now see host's curse layout, not vanilla)

v0.7.20 fixed the shop_view nil crash by gating the `deus_populate_graph` hook on `is_server` — clients passed through to vanilla, never crashed. But clients still produced a VANILLA local graph while host produced a MUTATED one, so the map and theme on each peer differed (client saw wrong curse on a mission, wrong god on the map).

v0.7.21 replaces the `is_server` gate with proper sync:

1. **Host broadcasts effective settings** at the end of `DeusRunController.setup_run` via VMF's `mod:network_send`. Sent BEFORE the engine's `full_sync` RPC so clients receive the settings before their own `setup_run` triggers `deus_populate_graph`. Settings synced: `cursed_mission_count`, `replace_shrines_with_missions`, `disable_dominant_god`.
2. **Clients receive and stash** in a `_ct_host_settings` table via `mod:network_register("ct_sync_host_settings", ...)`.
3. **The graph hook uses `effective_setting(name)`** instead of `mod:get(name)`. On host this returns the user's actual setting; on client it returns the host's most-recently-broadcast value. If the broadcast hasn't arrived yet (first run, RPC ordering), falls back to vanilla-equivalent defaults — same safety as v0.7.20's gate.

Net effect: with host running e.g. `cursed_mission_count = 30, disable_dominant_god = true`, all peers now produce the same graph from the same seed. Map shows the same cursed nodes for everyone, themes match, no more "wrong curse on a mission" desync.

### Tweaked: Belakor lighting — brightened interior, slightly dimmed exterior

User feedback: Belakor interiors were almost pitch-black. Bumped `ambient_tint` from `{0.45, 0.40, 0.75}` to `{0.75, 0.65, 1.00}` (brighter purple-ish bounce), `ambient_tint_top` from `{0.35, 0.30, 0.80}` to `{0.60, 0.55, 1.00}` (brighter zenith), `secondary_sun_color` slightly brighter too. `skydome_tint_color` and `sun_color` dimmed slightly so the outdoor still feels oppressive. `exposure_mul` from 0.85 → 0.92 (less overall darkening).

## 0.7.20-alpha (2026-05-14)

### Fixed: `deus_shop_view_v2.lua:182: attempt to index field '_shop_config' (a nil value)` crash on client when host/client mod settings differ

Crash reported by user (client) when client had `replace_shrines_with_missions = true` (shops off, converted to missions) and host had it false (vanilla shops on).

Root cause: CW graph generation is deterministic from seed — both peers call `deus_populate_graph` independently (`rpc_deus_setup_run` triggers it on clients). Our hook fired on BOTH peers with their own settings:
- Host: hook saw `replace_shrines_with_missions = false`, no mutation, graph kept SHOP nodes with `level = "shop_strife"` etc.
- Client: hook saw `replace_shrines_with_missions = true`, converted SHOP→TRAVEL with `label = 0`, vanilla level picker then rolled a random TRAVEL level (e.g. `pat_mountain_wastes_path1`) for that node.

Host transitioned the run to the shop node and loaded `shop_strife.level`. Shop UI opened on both peers via flow events. Client's `DeusShopSettings.shop_types[<client's mutated level>]` returned nil → crash on the `_shop_config.blessings` index.

Fix: gate the entire `deus_populate_graph` hook behind `Managers.player.is_server`. Clients now pass straight through to vanilla; their local graph matches what host would have generated without our overrides. UI lookups won't nil-crash because every node has its vanilla level/type. Host's mutations still drive the authoritative shared state.

This same fix prevents future similar bugs from `cursed_mission_count`, `disable_dominant_god`, `filter_available_curses`, and any other graph-modifying override that has differing values between peers.

## 0.7.19-alpha (2026-05-14)

### No code changes — version bump to force Steam Workshop CDN refresh

Friend's subscriber client pulled v0.7.17 despite v0.7.18 being uploaded and the Steam Web API correctly reporting `file_size = 1,399,303`. Steam CDN edges can serve stale content for hours after a metadata update. Bumping MOD_VERSION (visible in chat echo) changes the bundle hash and forces fresh CDN propagation.

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

New checkbox in the Modified Boons group. The Movement Speed boon is a one-of-a-kind reward awarded on mission completion in Chaos Wastes (boon-treated, not a buff stack). Vanilla `MorrisBuffTweakData.movespeed` is `{ description_value = 0.05, multiplier = 1.05 }`. `deus_power_up_settings.lua` bakes both into runtime tables: the multiplier into `DeusPowerUpBuffTemplates.power_up_movespeed_{common,rare,legendary}.buffs[1].multiplier` (1.05 in all three rarity entries), and the description_value into `DeusPowerUpTemplates.movespeed.description_values[1].value` (single 0.05 entry, referenced by all rarities). The tweak save-and-restores both: writes 1.10 to each rarity's multiplier and 0.10 to the description value. The in-game tooltip auto-reflects "10%" because vanilla `description_properties_movespeed` is formatted off `description_values`.

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
