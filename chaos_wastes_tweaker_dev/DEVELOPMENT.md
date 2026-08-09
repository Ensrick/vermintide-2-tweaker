# Chaos Wastes Tweaker — Development Notes

Engine gotchas, crash modes, and load-bearing patterns specific to `chaos_wastes_tweaker` (ct). Read alongside `CHANGELOG.md` (version history), `TODO.md` (planned features), `CW_HANDBOOK_TRAITS.md` (CW-exclusive trait reference), and the repo-root `DEVELOPMENT.md` / `CROSS_MOD_ARCHITECTURE.md`.

This file is for HOW the CW-side internals work (so we don't re-burn the same crash twice). Operational rules (no rm -rf, version bump, deploy doctrine, etc.) live in `PROJECT_STANDARDS.md` and the repo root.

## Boon runtime module contracts

The entry manifest owns orchestration; boon behavior is split by state owner and loaded once, in this order:

1. `_ct_boon_balance.lua` owns reversible mutations of vanilla boon tables and defeat-recovery state access. New vanilla-boon numeric/save-and-restore work belongs here.
2. `_ct_boon_registry.lua` owns deterministic `NetworkLookup` registration, boon pool insertion/removal, dormant/Skulls scaffolding, and miracle registration. New lookup or rarity-pool work belongs here.
3. `_ct_meta_trait_boons.lua` owns CT-authored meta/trait boons, peer-parity stripping, resource hooks, buff observation, and Endless Bombs lifecycle hooks. New CT boon behavior belongs here.

`chaos_wastes_tweaker_dev.lua` constructs a short-lived `mod._ct_boon_runtime_context`, calls each module exactly once at the original contiguous block's load point, then clears the context. Modules localize their dependencies during load and expose only bounded return tables. They must not `dofile` one another, move hooks to a later lifecycle callback, or take ownership of settings/RPC state already owned by the entry file. Preserve this order because registry consumers in the meta module require both earlier contracts and hook registration order is observable.

The structural guard is `qa/lua/tests/test_ct_boon_split.lua`; the repository size ratchet is `qa/check_file_sizes.ps1`. The entry file must remain at or below its frozen 9,872-physical-line baseline (the matching 9,314 non-empty-line ceiling lives in `qa/decomposition_contracts.psd1`), and no extracted module may cross the 2,500-line hard limit.

### `/ct_regression_test` suite module (`_ct_regression.lua`) — issue #2 / OOP W5

The bulk of the `/ct_regression_test` check suite is extracted VERBATIM to `_ct_regression.lua` (2026-07-18). It is a pure installer — `return function(mod, ctx)` — dofiled ONCE at the suite's original position in the entry (after the sibling modules that set its marker globals, before the trailing feature dofiles), so append order into `_RT_CHECKS` (= the printed check order) is unchanged. It registers through `mod._ct_rt_register` (the shared registrar the entry still owns); it never creates a second `_RT_CHECKS` and never `dofile`s a sibling. Its `ctx` header wires the entry's immutable marker constants, stable helper functions (`_ct_meta_ammo_cost_multiplier`, `_clamp_network_bounded_max`, the `_dump_pickup_*` forward-decls, `_dbg`/`_dbg_alert`), config tables, and the `_ct_mutex` framework object; each check body below the header is byte-identical to its former inline form. Marker globals the checks read (e.g. `CT_NO_ROAMERS_ARITY_FIX_MARKER`, the `_CT_CHUNK_*` paced-send set, cross-module `CT_COT_471_DIAG_MARKER`/`CT_ENDLESS_BOMBS_MARKER`) stay `_G` globals set by the entry or sibling modules before any command runs, so they resolve at call time. ONE check stays inline in the entry: `starting_coins_value_matches_setting` reads the mutable `_starting_coins_applied_for_run` upvalue, which the `setup_run` starting-coins hook updates per run — moving it would freeze that read at the dofile-time nil (the dropped-upvalue burn class). New checks that lock a specific fixed issue go in `_ct_regression.lua` (name them `issueNNN_<slug>`); a check that must read live mutable entry state stays inline like the starting-coins one. The structural guard is `qa/lua/tests/test_ct_entry_decomposition.lua`.

### Command owner (`_ct_command_owner.lua`) — issue #1159

The 13 CT diagnostics and maintenance commands are extracted VERBATIM to one pure installer: `return function(ctx)`. The entry calls it exactly once after `mod.on_disabled` and before `_ct_regression.lua`, preserving registration order and the original settings-lifecycle boundary. Its five injected dependencies are `mod`, `AdventurePool`, `_dump_pickup_system_state`, `effective_setting`, and `MOD_VERSION`; game globals used inside callbacks remain late-bound. The owner registers no hooks, RPCs, lifecycle callbacks, or update loop. `/force_inject_pool` remains the only mutating command and runs only when explicitly invoked; command `mod:echo` output remains explicit user-requested feedback. Add new CT diagnostics/maintenance commands to this owner, not the entry. `qa/lua/tests/test_ct_command_owner.lua` guards order, cardinality, wiring, placement, and install-time inertness.

### Journey-stat difficulty guard (`_ct_journey_difficulty_guard.lua`) — issue #291

The verified journey-completion crash guard is a direct `return function(mod)` installer loaded once after replacement-progression setup and before the consolidated `DeusRunController.setup_run` hook. It owns the sole CT hook on `StatisticsUtil._register_completed_journey_difficulty` and assigns `CT_JOURNEY_DIFFICULTY_GUARD_MARKER` synchronously before `_ct_regression.lua` installs. The 39-line implementation is byte-identical to its former entry block: only an unsupported RECORDED journey difficulty is clamped to the final value returned by `get_default_difficulties`; gameplay difficulty is untouched. It captures only `mod`; engine globals remain late-bound. Do not fold progressive-difficulty state, settings synchronization, RPCs, or logging migrations into this owner. `qa/lua/tests/test_ct_journey_difficulty_guard.lua` guards hook cardinality/order, pass-through arity and multiple returns, clamp behavior, marker availability, test-global cleanup, and the optional decompiled vanilla source contract.

### Starting-Boon Preview helper owner (`_ct_boon_preview_helpers.lua`) — issue #461 / #1159

The six pure/helper surfaces for the Tab-hold Starting-Boon Preview are extracted byte-for-byte to a `return function(ctx)` installer whose only injected dependency is `mod`. It loads once after `_ct_boon_preview_tooltip.lua` plus `_ct_boon_preview_runtime.lua` and before `IngamePlayerListUI._setup_deed_reward_data` consumes the helpers. Engine globals remain late-bound. The requested whole #461 heading block is not a safe single-feature owner: its one `IngamePlayerListUI._draw` hook intentionally composes #461 tooltip/rows with #533 collectibles and #571 recovery, and VMF silently drops a duplicate hook on the same class/method pair. Therefore that shared hook, the setup hook, diagnostics, command, and inline regression checks remain at their original manifest seam. Do not move or split that hook until a dedicated composite panel owner can take all three concerns together. Add data/identity/widget-construction helpers here; keep cross-feature panel composition in the entry. `qa/lua/tests/test_ct_boon_preview_helpers.lua` guards exact extracted bytes, the one-dependency seam, helper cardinality, manifest placement, shared-hook cardinality, engine-free behavior, and global cleanup.

### Weapon-trait generation owner (`_ct_weapon_trait_generation.lua`) — issue #1159

Weapon trait-pool mutation and post-roll tiering are one stateful owner installed at the original generation boundary, immediately after `DeusRunController.get_deus_weapon_chest_type` and before the `force_belakor` override. Its injected contract is only `mod`, `effective_setting`, `_dbg`, and `_rt_register`; `DeusWeapons` and `WeaponTraits` stay late-bound because the engine and peer mods may populate them after script load. The owner registers exactly four `DeusWeaponGeneration` hooks, in order: `generate_weapon`, `generate_weapon_for_slot`, `generate_item_from_item_key`, then `upgrade_item`. Every wrapper preserves nilable trailing arguments, brackets vanilla with temporary trait-pool apply/restore, restores even when vanilla throws, then applies tier-by-rarity and the final detached-result ban filter in the original order.

The module retains the public `mod._ct_get_trait_class_pools` and `mod._ct_strip_banned_traits_from_result` surfaces. Its two lazy caches live in `mod._ct_weapon_trait_generation_state`; `mod._ct_reset_weapon_trait_generation_caches()` clears both and is called from `mod.on_disabled`. Re-evaluating the installer refreshes injected dependencies and callback dispatch but does not register another check or hook. Do not split the four hooks from their shared save/restore state or cache lifecycle. `qa/lua/tests/test_ct_weapon_trait_generation.lua` guards the manifest boundary, exact hook/check order and cardinality, idempotence, public APIs, nilable arity, throw-path restoration/log policy, melee/ranged tier behavior, final ban stripping, and both cache resets.

### Bot weapon-chest / reusable-altar owner (`_ct_bot_weapon_chest_owner.lua`) — issue #1159

Bot weapon generation/equip, chest diagnostics, reusable-altar purchase presentation, and the consolidated `DeusChestExtension.open_chest` post-work form one bounded installer at their original boundary. It registers exactly `extensions_ready`, `purchase`, then `open_chest`; the latter remains the sole CT hook on that pair and still runs vanilla once before altar re-arm, boon no-repeat bookkeeping, and bot weapon mirroring. The separate #211 grant-source hooks remain inline immediately before the installer.

The entry owns the resettable `_altar_uses_by_go_id` table, so the module receives a late-bound accessor rather than capturing one table generation. Its other injected dependencies are the effective-setting and log functions, altar max-use policy, collected-peer probe, and bounded probe-watch table. The public `mod._ct_bot_equip_weapon` surface is a stable dispatch wrapper; reinstall refreshes dependencies without adding hooks. Keep the purchase/open transaction together: the temporary bot altar price is restored on the vanilla error path, and the purchase flow-event filter is always restored without retrying a possibly charged purchase. `qa/lua/tests/test_ct_bot_weapon_chest_owner.lua` guards placement, grant-hook separation, hook order/cardinality, idempotence, the public surface, per-event-manager subscription, collapse filtering/restoration, vanilla-error restoration, and boon no-repeat bookkeeping.

### Boss Grudge Marks owner (`_ct_boss_grudge_marks.lua`) — issue #107 / #1159

The Boss Grudge subsystem is one bounded owner at its original late-runtime
boundary. It captures the 13-entry native `_G.BossGrudgeMarks` baseline once,
restores that stable baseline before every settings sync, filters the universal
`TerrorEventUtils.apply_breed_enhancements` host path, and owns
`/dump_grudge_marks` plus `/verify_grudge_marks` in their original registration
order. The entry retains only the returned `sync` facade used by
`on_setting_changed`; it does not move or own #426 settings collection/RPCs.

The returned owner map is exactly `{ sync, names, get_baseline }` and is stable
across reloads. Effective settings, umbrella policy, globals, Managers, debug,
and printf are refreshed call-time dependencies; the hook and two commands are
registered at most once. A reload therefore cannot snapshot an already-filtered
set as its new vanilla baseline. Add Boss Grudge filtering/diagnostics here,
never to a second terror-event hook or the general command owner.
`qa/lua/tests/test_ct_boss_grudge_marks.lua` exhaustively guards owner headers,
map exports, 13-name order, hook/command cardinality and order, baseline restore,
host filtering, late dependencies, and Phase-4 wire isolation.

### Curse-lighting / injected-map performance owner (`_ct_curse_lighting_owner.lua`) — issues #104 / #258 / #271 / #1159

The curse sky profiles, per-map brightness overrides, current-node helpers, and
the injected-map performance census form one bounded owner at the original
`CameraManager.shading_callback` boundary. It registers exactly that one hook,
after the networked-flow-state guards and before shrine replacement. The hook
retains the original gate, census-before-theme order, log text, shading channel
order, and scalar behavior.

The private state owns stable helper and profile-table identities. Every install
refreshes its eight action-time dependencies, then exhaustively republishes the
seven-field public map into the current `mod._ct_curse_lighting_owner` table:
three node helpers, two data tables, the census marker, and the five-second
window. A reload may replace that public map and dependencies, but cannot add a
second hook or retain removed/foreign exports. The legacy
`CT_PERF_CENSUS_MARKER` and `CT_PERF_WINDOW` globals are republished before
the idempotence guard; the later Be'lakor pickup seam consumes only the returned
`current_node_is_belakor` facade.

Add curse-atmosphere data, map overrides, node-state helpers, or the performance
census here. Do not add another CameraManager shading hook, command/RPC owner,
or Phase-4 settings-sync work. `qa/lua/tests/test_ct_curse_lighting_owner.lua`
guards exact placement and hook cardinality, fresh-map exhaustive replay,
function/table identity, distinct-dependency action-time dispatch, data values,
and both legacy performance globals.

### Spawn-eligibility owner (`_ct_spawn_eligibility_owner.lua`) — issue #1159

Every "may this pickup claim this spawner?" decision is one bounded installer:
the career-exclusive blocklist denial (v0.7.97), the v0.7.165-dev coin-starvation
reservation that guarantees a ~40% coin-only spawner slice under the
Abundance-of-Life curse, the v0.7.78 unit-loadability pre-flight, and the v0.7.64
injected-adventure campaign-category fallback. It registers exactly one hook,
`PickupSystem._can_spawn`, which stays the sole CT hook on that pair. The
Belakor-locus gate deliberately remains inline in the entry: it is the
`force_belakor` feature's gate, not a spawn-eligibility decision.

The owner installs LATER in the entry than the `populate_pickups` hook that calls
`mod._ct_rebuild_coin_reserved_set`. That is safe and intentional — the populate
hook resolves the field at call time, and the entry's script body completes
before any hook fires — so the install site must stay after it, exactly where the
pre-extraction helper block sat.

Its public surface is unchanged: `mod._ct_coin_reservation_test` (the
`coin_reservation_partition` regression marker), `mod._ct_rebuild_coin_reserved_set`,
`mod._ct_clear_coin_reserved_set`, and `mod._ct_spawner_reserved_for_coins`.
The two per-run telemetry tables arrive as **getters, not values**: the entry
REASSIGNS `_career_exclusive_denial_counts` and `_career_exclusive_logged_this_run`
to fresh tables at every populate entry (run boot), so a captured reference would
pin this owner to the load-time tables — denial counts would accumulate across
runs and the once-per-run log gate would never reset. Add spawner-eligibility
rules here, never as a second `_can_spawn` hook.
`qa/lua/tests/test_ct_spawn_eligibility_owner.lua` guards dofile cardinality,
hook exclusivity, wholesale helper migration, the four-field public surface,
install ordering against the populate consumer, and the getter seam on both ends.

### Pickup-spawn owner (`_ct_pickup_spawn_owner.lua`) — issue #1159

The orthogonal half of the same question. Eligibility decides *may this pickup
claim this spawner*; this owner decides **what the claimed spawner produces and
what it pays out**. The two share no hook and no helper, and this one installs
immediately BEFORE the eligibility owner, at the exact slot its block occupied
pre-extraction. Four hooks live here and nowhere else in the mod:

| Hook | Job |
|---|---|
| `PickupSystem._spawn_pickup` | collectible → Pilgrim's Coin identity rewrite, the #294 non-resident residency guard, and the #58/#143 census tap. Preserves BOTH vanilla return values (#322). |
| `UnitSpawner.spawn_network_unit` | the same rewrite for chest loot dice, which bypass `PickupSystem` entirely (#351). |
| `PickupSystem._spawn_guaranteed_pickup` | the book-pedestal ladder: Chest of Trials (cap-budgeted, including natively baked `deus_cursed_chest` spawners, #60) → Bel'akor locus → 1.75x big coin casket → empty. |
| `GameModeDeus._get_coins_amount_and_type` | the 3x payout for the `ct_big_casket`-tagged casket. |

Unlike the eligibility owner, this one is a **bare dofile** (no `install(ctx)`),
so the body runs at file scope exactly as it did in the entry — that is what
keeps hook-registration order and the load-time provenance markers
(`CT_MORGRIM143_MARKER`, `CT_MORGRIM143_RENORM_MARKER`,
`CT_PICKUP_RESIDENCY_GUARD_MARKER`, `CT_SPAWN_PICKUP322_MARKER`) byte-identical.
Entry helpers arrive through the `mod._ct_*` seams the entry publishes earlier in
its own chunk: `mod._ct_effective_setting`, `mod._ct_on_injected_adventure_level`,
`mod._ct_adventure_base_from_level_key`, and
`mod._ct_curse_lighting_owner.current_node_is_belakor`.

The two per-level counters `populate_pickups` resets —
`mod._ct_chest_conversions_this_level` and
`mod._ct_belakor_altar_spawned_this_level` — are **`mod` fields, not file-locals**.
They were entry locals only so the lexically-earlier populate hook could bind them
at closure-creation time; a separate chunk cannot reach that binding, and a
surviving `local` would split the state (the entry resetting a local nobody reads
while this owner increments a nil field). `populate_pickups` keeps sole ownership
of the reset; this owner owns every increment.
`qa/lua/tests/test_ct_pickup_spawn_owner.lua` guards dofile cardinality, per-hook
exclusivity across entry/owner/eligibility, install ordering, moved-local orphans,
the mod-field counter seam, marker migration, and the eight-field public surface.

## Buff registration: dormant boons need dual-table writes

When ct injects a previously-dormant CW boon into the active loot pool at runtime (e.g. the `activate_dormant_*` toggles), the buff template **must** be registered in BOTH:

1. `DeusPowerUpBuffTemplates[buff_name]` — for vanilla CW infrastructure that introspects this table
2. `_G.BuffTemplates[buff_name]` — for `BuffUtils.get_buff_template()` to find it at apply time

**Why:** vanilla flow is:
- `scripts/settings/dlcs/morris/morris_buff_settings.lua:7310` calls `table.merge_recursive(dlc_settings.buff_templates, DeusPowerUpBuffTemplates)`.
- DLCUtils then merges `dlc_settings.buff_templates` into the global `BuffTemplates`.
- Both merges run at boot, BEFORE any mod loads.

`BuffUtils.get_buff_template(name)` (`buff_utils.lua:256`) reads `BuffTemplates[name]`. If ct writes only to `DeusPowerUpBuffTemplates` at runtime, the boon appears in the loot pool but the buff system cannot find its template. Result: `buff_extension.lua:177` crashes with `attempt to index local 'buff_template' (a nil value)` the first time the boon is rolled and applied.

**How to apply:** any code that mutates loot-pool registrations at runtime (dormant activation, mod-provided boons, custom boon injection) must write to both tables. The same rule applies to other DLC-merged template tables — assume any `DLCSettings.morris.*` source has already been merged at runtime.

**Burn history:** ct v0.7.31 (dormant boon activation) → toggling `activate_dormant_*` put the boon in the shrine pool → first apply crashed → fixed v0.7.32 by adding `_G.BuffTemplates[name] = buff_template` alongside the existing `DeusPowerUpBuffTemplates` write.

## Deus boon rarities: event / rare / exotic / unique only

`DeusPowerUpRarities` is the sequential list of valid **boon** rarities:

```lua
-- scripts/settings/dlcs/morris/deus_power_up_settings.lua:7032
DeusPowerUpRarities = { "event", "rare", "exotic", "unique" }
```

`common` and `plentiful` are NOT in this list. They exist in `DeusDropRarityWeights` for WEAPON drops (white/green tier) but boons skip them entirely. There is no "common-tier boon" in CW.

When a mod injects a boon into `DeusPowerUpRarityPool[<rarity>]` at a rarity not in `DeusPowerUpRarities`, the boon **does** enter the pool, but it crashes when it's rolled and added to `existing_power_ups`:

```lua
-- deus_power_up_utils.lua:189
existing_power_ups_lut[power_up.rarity][power_up.name] = DeusPowerUps[power_up.rarity][power_up.name]
```

`existing_power_ups_lut` is file-scope, built from `DeusPowerUpRarities`:

```lua
-- deus_power_up_utils.lua:179
local existing_power_ups_lut = table.select_map(table.set(DeusPowerUpRarities), function (_, rarity)
    return {}
end)
```

If `power_up.rarity == "common"`, `existing_power_ups_lut["common"]` is nil → `nil[power_up.name] = ...` crashes with "attempt to index a nil value."

**Symptom:** `[Script Error]: scripts/helpers/deus_power_up_utils.lua:208: attempt to index a nil value`. Stack frame is `generate_random_power_up`. The crash typically appears far from the injection site, after many shrine visits — the boon has to be rolled into `existing_power_ups` before the bad lookup fires.

**Rule:** any mod-injected boon must pick a rarity from `{event, rare, exotic, unique}`. If migrating a "tier 1 / common" mental model, map T1 → `rare` (lowest valid). `event` is reserved for seasonal Skulls boons and may have additional gating; avoid unless mirroring an existing event boon.

**Burn history:** ct v0.7.34 → v0.7.36 with dormant-boon injection of `squats` and `deus_larger_clip` at `common` rarity. Fixed v0.7.37 by remapping both to `rare`.

## Jewelry traits are CW boons, not weapon traits

In **adventure mode**, traits live on three item slots: weapons, jewelry (necklace / charm / trinket), and (career-specific) items.

In **Chaos Wastes**, jewelry traits do NOT appear as item-bound traits. Every necklace / charm / trinket trait is registered in `DeusPowerUpTemplates` as a **boon** — picked up at altars or from chests of trials, identical mechanically to other CW boons.

**Weapon traits remain weapon traits in both modes.** The CW-exclusive weapon traits (Shard Strike, Bloodthirst, Deadeye, etc., see `CW_HANDBOOK_TRAITS.md`) live in `WeaponTraits` and attach to the equipped weapon — not the boon pool.

**Examples of jewelry-trait-as-CW-boon:**
- `decanter` — charm trait `trait_ring_potion_duration` ("+50% potion duration") → CW boon "Decanter"
- `home_brewer` — charm trait ("chance to not consume potion") → CW boon "Home Brewer"
- `barkskin`, `natural_bond`, `boon_of_shallya`, `hand_of_shallya`, `healers_touch`, `grenadier`, `explosive_ordinance`, `shrapnel`, `concoction`, etc. — all in `DeusPowerUpTemplates`.

**Verified via:** `/dump_boon_loc` command — `decanter`, `home_brewer`, `barkskin`, etc. all appear as entries in `DeusPowerUpTemplates`. The advanced description loc key (`description_trait_ring_potion_duration` etc.) preserves the original adventure-mode trait origin, but the CW gameplay surface is always the boon pool.

**How to apply:** when the user mentions any of these names, default to thinking of them as CW boons, not weapon traits. Burned in a v0.7.47 follow-up discussion (Decanter mis-categorized as weapon trait).

## Custom boon design: max_overcharge buff key (`reduced_overcharge` is safer)

`max_overcharge` (NOT `max_overheat_modifier` — older notes were wrong) is the stat_buff key that scales `overcharge_extension` capacity for Sienna staves AND Bardin drakefire weapons. Defined in `scripts/unit_extensions/default_player_unit/buffs/buff_templates.lua:109` as `max_overcharge = "stacking_multiplier"`. Read by `PlayerUnitOverchargeExtension._calculate_and_set_buffed_max_overcharge_values` (`player_unit_overcharge_extension.lua:106-108`):

```lua
local max_value = self._buff_extension:apply_buffs_to_value(self.original_max_value, "max_overcharge")
```

Recalc only fires at `extensions_ready` and on `trigger_procs("on_overcharge_lost")`. Adding the buff via `add_buff` mid-game does NOT immediately refresh — must wait for one of those hooks (or weapon swap → wield).

**What it covers:**
1. **Sienna staves** — firebolt, beam, conflagration, fireball, geiser. All use `weapon_template.overcharge_data` + `overcharge_extension`.
2. **Bardin drakefire weapons** — `drakegun` and `brace_of_drake_pistols`. Both have `weapon_template.overcharge_data` and use `overcharge_extension`.

**What it does NOT cover:**
- **Moonfire Bow** (`we_deus_01`): uses `energy_system` via `PlayerUnitEnergyExtension`. The extension reads `_max_energy = energy_data.max_value or 40` at `init` and never calls `apply_buffs_to_value` on it. No buff path exists for max energy. (`ammo_used_multiplier` works on per-shot drain, but not on the max.)
- **True bow ammo** (Hagbane, Swift Bow, Longbow, etc.) — covered by `total_ammo`, not overcharge.
- **Vanilla bows + crossbow** — already covered by `total_ammo`.

**Why we use `reduced_overcharge` instead of `max_overcharge` in Quiver Cascade (ct_meta_ammo):** the engine `NetworkConstants.max_overcharge` upper bound is ~60 (vanilla designed it for Sienna Scholar's +50% talent: 40 base × 1.5 = 60 exactly). ANY higher value crashes both host and husk on the per-frame `update()` call with `fassert(max_value >= ... and max_value <= ...) "Max overcharge outside value bounds allowed by network variable!"` at `player_unit_overcharge_extension.lua:110`.

The bound lives in the compiled engine `.network_config` binary and is NOT widenable from Lua — `NetworkConstants.max_overcharge` is a read-only snapshot from `Network.type_info` at boot, and the transport layer (`GameSession.set_game_object_field` for `overcharge_max_value`) uses the engine's own type-info, not the Lua table.

Fix (shipped v0.7.80-alpha): replaced `{ stat_buff = "max_overcharge", multiplier = 0.05 }` with `{ stat_buff = "reduced_overcharge", multiplier = -0.05 }`. The new key reduces overcharge **generated per cast** (consumed locally inside ActionThrowProjectile / overcharge-add paths — not network-synced as a max value), so gameplay effect = "more casts before overheating." Zero crash risk regardless of boon count.

**Burn history:** Co-op session (Sienna host + Bardin drakefire client) — both crashed at 12 stacks (40 → 64, exceeding 60 cap). Fixed v0.7.80-alpha.

## Adventure-injected levels strip incompatible mutators

When ct's `inject_adventure_maps` is on, the player can land in a CW node whose conflict director is a vanilla campaign director (`chaos_light`, `beastmen`, `skaven_light`). Some `PackSpawningSettings` entries in `conflict_settings.lua` lack the `difficulty_overrides` field that CW pacing mutators expect — notably `chaos_light` at line 4795 has only `area_density_coefficient`, `basics`, `roaming_set`.

CW's `mutator_deus_pacing_tweak` applies the `no_roamers` mutator to SIGNATURE zones. Its `tweak_pack_spawning_settings` callback iterates:

```lua
for _, difficulty_override in pairs(pack_spawning_settings.difficulty_overrides) do
    difficulty_override.area_density_coefficient = 0
end
```

If `pack_spawning_settings.difficulty_overrides == nil`, `pairs(nil)` crashes:

```
[Script Error]: scripts/settings/mutators/mutator_no_roamers.lua:6:
  bad argument #1 to 'pairs' (table expected, got nil)
```

(Reported line varies between vanilla and production due to comment differences — production reports line 6 even though the `pairs` call is at line 8 of the decompiled source.)

**Fix shape (ct v0.7.41):** hook `MutatorHandler.tweak_pack_spawning_settings` and strip `no_roamers` (and other incompatible mutators) from the zone-mutator and per-pack-spawn mutator lists when the current level is adventure-injected. Vanilla CW levels are untouched — their `pack_spawning_settings` have `difficulty_overrides` and `no_roamers` is safe there. Detection via `on_injected_adventure_level()` (defined in `chaos_wastes_tweaker.lua` near `adventure_base_from_level_key`).

**Alternative considered + rejected:** defensive patch adding `difficulty_overrides = {}` to every `PackSpawningSettings` entry at mod load. Would unblock the crash but doesn't honor design intent — `no_roamers` was authored for CW pacing, not campaign. Stripping the mutator is cleaner.

**How to extend:** when a new mutator or pacing rule crashes on adventure-injected levels with a similar nil-field signature, add its name to `ADVENTURE_INCOMPATIBLE_PACK_MUTATORS` near the `MutatorHandler` hook.

## Peer-parity wire safety for modded boons and miracles (issue 426)

**The invariant:** nothing ct puts on a vanilla wire path may be unresolvable by a no-mods peer. ct's modded boons (`power_up_ct_boon_*`, `ct_meta_*`, `ct_kill_heal`) and miracles (`ct_miracle_*`) register into `NetworkLookup.buff_templates` / `deus_power_up_templates` unconditionally (index parity across ct peers - never gate registration, see inject_dormant_boon's v0.7.67 comment). But GRANTING or APPLYING that content sends the modded index to every peer, including non-ct peers (ct's `create_network_hash` shim deliberately lets them join): `rpc_add_buff` broadcast (`buff_system.lua:302-305`, decode fatal :430), deus run-state power-up sync (`deus_run_state_spec.lua:60/:85`), persistent-buff reapply (`deus_spawning.lua:249/:277-278`), hot-join buff re-send (`buff_system.lua:1087-1104`).

**The gate (v0.7.240-dev, hot-join fence v0.7.291-dev, exact catalog v0.7.322-dev):** peer-parity beacon - a verbatim copy of `tools/shared_lib/_lib_peer_parity.lua` (master; DO NOT edit the copy - edit the master and re-copy) instantiated on channel `ct_boon_catalog_exact_v1` with `CT_RPC_SCHEMA` and `opts.wire_identity`. Fail-safe: modded content inert until every other human peer positively acks; solo enables immediately; beacon failure keeps content off. Six surfaces, all in `_ct_meta_trait_boons.lua` (search `[ct:426]`):

1. **Pool membership** - `_ct_eject_modded_pools` / `_ct_inject_modded_pools` around `DeusPowerUpRarityPool`, driven by the gated feature `ct_modded_boons_miracles`; includes a load-time initial eject (the lib never fires `on_disable` for its INITIAL disabled state, so without the manual eject a never-acking peer would keep the load-time pool inserts live forever).
2. **Grant choke point** - parity filter inside the consolidated `DeusRunController.add_power_ups` hook (beside the issue-211 disable gate). Covers every grant source.
3. **Starting boons** - parity filter in the `_add_initial_power_ups` hook_safe; modded names only.
4. **Miracles** - `_try_buy_blessing` degrades Ulric/Isha to the vanilla blessing under unconfirmed parity; the Isha one-mission arm/apply is parity-gated with pending state preserved (retries next mission).
5. **Parity-loss strip** - debounced (15s) destructive cleanup on the host: modded player and party power-ups out of every synchronized SharedState row, ct names out of persistent-buff rows, live ct buffs off units via `remove_server_controlled_buff` (integer-id RPC, no-ops on peers without the buff). The debounce exists because the beacon disables instantly on an un-acked peer - a ct friend's ack-in-flight transient must not nuke the lobby's boons - and must exceed the lib's `ANNOUNCE_EVERY` (10s): VMF's `network_send` silently skips peers whose VMF handshake hasn't completed, so the arrival-triggered announce can be lost and the retry is the only delivery. Never strip in `on_disable` directly, and never set the grace below the announce cadence.
6. **Pre-roster hot-join fence** - `GameNetworkManager.hot_join_sync` runs before `PlayerManager:add_remote_player` (`peer_states.lua:432/:450`), so polling alone is too late. `require_peer(peer_id)` makes that not-yet-enumerable peer part of the parity set synchronously. A positive acknowledgement passes. Unknown/missing CT strips the full synchronized CT state immediately, then calls vanilla. Strip failure skips native sync and requests `NetworkServer.kick_peer`; there is no wait or indefinite join block. `GameNetworkManager.remove_peer` forgets the acknowledgement so a later connection with the same id needs fresh proof.

**Exact catalog (v0.7.322-dev, #426 / #1191)** - the precondition for all six, not a seventh surface. Presence was never proof of index parity: two ct peers on different builds both acked while their boon integers disagreed, and the decode is a strict-`__index` fatal. `_ct_wire_policy.lua` owns the closed catalogs (12 power-ups + 21 buffs = 33 wire rows) and `reserve_lookups` claims both axes in SORTED name order from `_ct_boon_registry.lua`, ahead of any per-boon registration, so ids depend on the catalog alone rather than on which toggles ran. `_ct_install_peer_parity` then proves the catalog against the live registry and every table the grant path reads, captures an integrity snapshot, and builds the composite identity peers echo. `mod._ct_wire_safe()` re-proves that snapshot per call, so post-boot renumbering by a third party also reads as parity-absent. No identity means no beacon, which means every surface above holds content inert. The channel rename is part of the closure: an unconverted ct build would ignore the extra exact fields on the old channel and ack anyway. Still open: the #371 unconditional sender floors inside `DeusRunState.set_*` / `BuffSystem.add_buff`.

`/ct_426_diag` is the read-only evidence surface for this contract. It traverses the
same full SharedState tree as the strip (including departed-player rows), counts live
server-controlled CT buffs, audits bidirectional power-up/buff lookup registration,
and reports visible-peer acknowledgements. It never invokes the strip or changes a
pool, setting, run-state row, buff, or acknowledgement.

**Sharp edges for future work:**
- New modded boon? Register through `inject_dormant_boon` (it writes `_injected_dormants`, which is what `mod._ct_is_modded_power_up` and the strip consult) and pool-insert via `_add_dormant_to_pool` - the gate then covers it automatically. A modded boon that bypasses `_injected_dormants` is invisible to the gate = reintroduces issue 426.
- The parity guard on pool inserts lives INSIDE `_add_dormant_to_pool` (single pool-write primitive) because runtime callers keep appearing (`sync_host_dependent_state` re-runs `register_trait_boon` on every host-settings receipt; `on_setting_changed` on every `enable_boon_*` edit) and each would otherwise silently undo the eject. Do not add pool-write paths that bypass `_add_dormant_to_pool`.
- The bot random-boon picker (`_pick_random_for_rarity`) samples `DeusPowerUpsArrayByRarity` - a REGISTRATION table that is never ejected - and its grants re-enter `add_power_ups` under `_ct_bot_mirror_active`, which skips the pre-grant filter. Both the picker and the per-bot grant check carry their own parity rejection; keep that in mind for any new grant path that sets `_ct_bot_mirror_active`.
- New ct-owned buff template? Name it `ct_*` (or `power_up_ct_*`) - the strip predicate `mod._ct_is_ct_buff_template` is prefix-based, and no vanilla template uses those prefixes (grep-verified 2026-07-11).
- `mod.update` is wrapped twice at the wire-safety block (beacon tick + strip ticker), preserving ct's own update. Anything that REASSIGNS `mod.update` after that block kills the beacon - append by chaining, never assign.
- Hot-join safety must remain synchronous. Do not move the pending-peer fence below `func(self, peer_id, ...)`, add a grace before the immediate strip, or revert full-state traversal to PlayerManager rows; each reopens the pre-roster or stale-row wire exposure.
- The `ct_peer_manifest_chunk` `/peers` machinery is a DIAGNOSTIC dump, not a gate - do not bolt gating onto it; the beacon is the live authority.

## Curse-mutator MAX_HEALTH rank hole at cataclysm_3 (vanilla bug ct patches)

**Vanilla Fatshark bug:** `mutator_curse_skulking_sorcerer.lua` declares broken rank constants (`CATACLYSM = 6`, `CATACLYSM_2 = 6` duplicate, `CATACLYSM_3 = 7` at :9-11). The `MAX_HEALTH` table its `server_initialize_function` reassigns onto `Breeds.curse_mutator_sorcerer` (:36) therefore spans ranks 2..7 and has **no entry at rank 8** (cataclysm_3). The base breed's own `max_health` is a full 8-entry array (`breed_chaos_mutator_sorcerer.lua:58-67`), so the hole only exists while the curse is initialized. Fatshark guarded the sibling `RESPAWN_TIME` lookup with `or RESPAWN_TIME[NORMAL]` (:43) but not `MAX_HEALTH`.

Vanilla CW never reaches rank 8, but ct's progressive difficulty can ramp a run to cataclysm_3 = rank 8 (`difficulty_settings.lua:287`). A curse-sorcerer spawn then resolves `max_health[8] = nil` (`conflict_director.lua:1948`), `GenericHealthExtension.init` throws in `math.clamp` mid extension-add, `extensions_ready` never runs (`entity_manager2.lua` add loop :116-146 precedes ready loop :150-171), and the half-initialized hit_reaction extension (registered one slot earlier, `unit_extension_templates.lua:403-419`) nil-derefs on the next HitReactionSystem update = host CTD. Issue 470.

**Fix shape (ct v0.7.239-dev):** UNCONDITIONAL backfill (issue 371 never-crash doctrine) via `mod:hook_safe(MutatorHandler, "initialize_mutators", ...)` - server-only call path (`mutator_handler.lua:48`) firing after every `template.server.initialize_function` (:644-645), i.e. after the sparse table lands on the breed. Sets `max_health[8] = 150` iff `[7]` exists and `[8]` is nil (150 = Fatshark's evident cataclysm_3 value; the duplicate-key bug shifted the band down one rank). Entries 6/7 deliberately untouched - re-keying would change live gameplay values. Predicate exported as `mod._ct_backfill_rank8_max_health`; regression test `curse_sorcerer_rank8_backfill`.

**Sweep note:** 2026-07-11 sweep of every `scripts/settings/mutators/mutator_*.lua` found no sibling instance - only skulking sorcerer assigns a rank-keyed table onto a Breed with an unguarded read (`egg_of_tzeentch` / `bolt_of_change` sparse tables all carry `or X[NORMAL]` / `or 1` fallbacks). If a future mutator lands a sparse rank table on a Breed field, extend the same `initialize_mutators` hook body with its own predicate + printf line rather than adding a second hook (VMF drops duplicate hooks silently).

## NetworkedFlowStateManager state-count leak (vanilla bug ct patches)

**Vanilla Fatshark bug:** `NetworkedFlowStateManager.clear_object_state` (`scripts/managers/networked_flow_state/networked_flow_state_manager.lua:493-495`) nils `_object_states[unit]` when EntityManager destroys a unit (`entity_manager2.lua:390`) **but never decrements `_num_states`**:

```lua
NetworkedFlowStateManager.clear_object_state = function (self, unit)
    self._object_states[unit] = nil
    -- BUG: should decrement self._num_states by the count of states this unit had
end
```

`_num_states` is monotonic for the life of the run. `flow_cb_create_state` (`networked_flow_state_manager.lua:379-406`) asserts `self._num_states < self._max_states` where `_max_states = 512`. Once the total spawn count of "units that ever held a networked flow state" passes 512, the next spawn fatals:

```
[NetworkedFlowStateManager] Too many object states(512).
```

**Reproduction:** any sufficiently long run with unit churn. Worst CW offender: the `cursed_chest_objective_unit` buff (`morris_buff_settings.lua:614` `apply_objective_unit`) applies to every cursed-chest enemy spawn. It spawns a `units/hub_elements/objective_unit` carrying a `chest_open_state` networked flow state. Each enemy = 1 permanently-leaked slot. With ct's adventure-mission injection + curses + multiple Chests of Trials per mission, the leak fills in 30–60 minutes.

Reproduced 2026-05-13 on `dlc_termite_3_khorne_path1` (Verminious Dreams khorne node) with `cursed_chest_count > 1`. Crash dump: `console-2026-05-14-03.23.33-d86fd894-2af0-4a4e-82d4-5e54759b32b9.log`.

**Patch (shipped v0.7.3-alpha):**

```lua
mod:hook("NetworkedFlowStateManager", "clear_object_state", function(func, self, unit)
    local unit_states = self._object_states and self._object_states[unit]
    if unit_states and type(unit_states.states) == "table" and type(self._num_states) == "number" then
        local count = 0
        for _ in pairs(unit_states.states) do count = count + 1 end
        if count > 0 then
            self._num_states = math.max(0, self._num_states - count)
        end
    end
    return func(self, unit)
end)
```

Counts states being released and subtracts BEFORE delegating to vanilla. `hook_safe` won't work — vanilla nils the table before the hook fires, leaving nothing to count.

**Consider porting** to other tweaker mods if the same crash signature shows up. The patch is generic and doesn't depend on CW state.

## Walk-through pattern: collision_filter, NOT scene_query

When a spawned CW unit (altar, Chest of Trials, etc.) blocks the player's path and you want them to walk through it without breaking "press E" interaction:

```lua
local num_actors = (Unit.num_actors and Unit.num_actors(unit)) or 0
for i = 1, num_actors do                  -- 1-indexed!
    local actor = Unit.actor(unit, i)
    if actor then
        Actor.set_collision_filter(actor, "filter_trigger")
        Actor.set_collision_enabled(actor, false)  -- belt-and-braces
    end
end
```

Key APIs:
- `Actor.set_collision_filter(actor, "filter_trigger")` — reclassifies the actor as a non-blocking trigger. The `filter_player_mover` sweep (player character controller) ignores `filter_trigger` actors.
- `Actor.set_collision_enabled(actor, false)` — extra safety in case some movers consult the enabled flag directly.

**DO NOT** also disable scene_query — that breaks interaction discovery:

```lua
-- WRONG — breaks "press E to open" prompts
Actor.set_scene_query_enabled(actor, false)
```

Interaction discovery in `GenericUnitInteractorExtension._find_best_interaction_unit` (vanilla `generic_unit_interactor_extension.lua:254`) uses a scene query:

```lua
PhysicsWorld.immediate_overlap(physics_world, "position", self_pos, "shape", "sphere",
    "size", 0.3, "collision_filter", "filter_overlap_interaction")
```

`filter_trigger` actors still match `filter_overlap_interaction` (and other interaction filters like `filter_interactable_in_chest`); `scene_query_enabled=false` skips them entirely, so the interaction prompt never appears.

**Burned twice in ct:**
- v0.6.16 → v0.6.19: 0-indexed `Unit.actor` loop silently no-op'd (`Unit.actor` is 1-indexed).
- v0.6.28 → v0.6.32: `set_scene_query_enabled(false)` broke Chest of Trials interaction. Fixed by switching to `set_collision_filter(actor, "filter_trigger")`.

Canonical vanilla example of the trigger-only pattern: `scripts/unit_extensions/human/ai_player_unit/ai_utils.lua:521` (warpfire-spewer backpack on death) — but that case disables both filter AND scene_query because the backpack is being destroyed; copy only the filter line for walk-through purposes.

## Lobby combined_hash and `inject_adventure_maps`

VT2's lobby compatibility check happens BEFORE any peer-to-peer communication or VMF host-sync can fire. The matchmaker computes a `combined_hash` from:

- `network_hash` (vanilla engine constant)
- `trunk_revision` (game build number)
- `engine_revision` (engine commit)
- `project_hash` (= "bulldozer")
- `lobby_data_version`
- **`num_levels`** — the only field a Lua mod can affect

If host's and joiner's `combined_hash` differ, the joiner gets `Join failed - Game version mismatch` (logged at `[ChatManager][1]System` + `PopupManager:queue_default_popup`). The check fires from `LobbyAux.create_network_hash` → `GameServerAux.create_network_hash`; visible in console as `Making combined_hash: <hex> from network_hash=... num_levels=<N>`.

`num_levels` = count of entries in the engine's `LevelSettings` table at the moment of join. Any mod that calls `LevelSettings[<key>] = <table>` raises the count globally for the session.

### Sticky LevelSettings mutations

`LevelSettings` entries CANNOT be cleanly un-registered from Lua. Once added, they persist until the game closes. Setting them to `nil` doesn't fully revert them — other game systems (`level_name` caches, `packages` references, network lookup tables) hold onto references. So:

- Toggling a mod's level-injection feature OFF mid-session does NOT reduce `num_levels`.
- Restarting the game IS the only reliable way to return to vanilla `num_levels`.

### ct's `inject_adventure_maps` is the canonical instance

`scripts/mods/chaos_wastes_tweaker/_adventure_pool.lua` `inject_pool()` adds each enabled campaign / event mission × 6 themes (wastes / khorne / nurgle / slaanesh / tzeentch / belakor) plus `_dupN` safety-threshold aliases. Default catalog ≈ 35 missions × 6 themes ≈ 210 entries; in practice ~192 (DLC-not-owned missions skip).

Vanilla `num_levels` = 582. With ct injection on (default missions enabled) = 774.

### What this rules out for "host-controlled" modding

You CANNOT make a `LevelSettings`-mutating feature "always sync to host" without a game restart. The lobby hash check is pre-mod-communication, and the mutation can't be undone in-session.

Workable patterns for a `LevelSettings`-touching feature:
1. **Lazy injection** — defer the mutation until the player creates a lobby AS HOST. Until then, `num_levels` stays vanilla and the player can join anyone. Cost: once they host, they're committed for the session.
2. **Clear toggle warning** — surface to the user that enabling this commits the session to matching peers only.
3. **Refactor away from LevelSettings** — inject via a mechanism the hash doesn't see (e.g. hook the CW node generator to substitute level bundles at runtime, never registering new `LevelSettings` entries). Significantly more work.

### Settings that ARE safely host-controlled

Any state stored in runtime tables not in the hash:
- `DeusPowerUpsArray` / `*ByRarity` — ct boon enable/disable
- `DEUS_CHEST_TYPES_DISTRIBUTION` — ct altar mix
- `MutatorHandler` state — ct curse disable
- `DeusWeapons[*].baked_trait_combinations` — ct trait ban
- `DeusRunController.on_soft_currency_picked_up` hook results — ct coin economy
- `DeusPowerUpTemplates.*.buff_template.buffs` — ct Khaine's Fury, bomb-boon cooldown

These hooks work freely; clients joining a vanilla / non-modded host work fine for these features.

### Diagnostic recipe

If a user reports "Join failed - Game version mismatch" with another modded player:

1. Get both `console-*.log` files (host + client).
2. Grep both for `Making combined_hash:` — compare `num_levels=N`.
3. If `num_levels` differs but `network_hash` matches, the cause is mod-induced `LevelSettings` mutation on at least one side. Identify which mod from mod-load lines.
4. Fix: disable the level-mutating feature on the higher-`num_levels` side AND restart VT2.

> Cross-mod note: this is also relevant to `lobby_tweaker`'s failed-join mod-list reveal. If `CROSS_MOD_ARCHITECTURE.md` gains a dedicated section on the lobby hash, cross-reference this section.

## Graph-snapshot RPC pattern (per-peer determinism fix)

When a load-time toggle in a mod mutates a globally-shared array that vanilla's deterministic generator indexes into, peers with different toggle states produce different output from the same RNG seed — even though every peer runs the "same" deterministic code. Settings-broadcast can't fix it because the array mutation already happened at module-load.

**ct v0.7.64 case:** `inject_adventure_maps` mutates `LEVEL_AVAILABILITY.TRAVEL/SIGNATURE/ARENA` at module-load. Vanilla `deus_populate_graph` picks levels by INDEX into those arrays. Same seed × different arrays = different per-node level/curse/theme picks across peers. The toggle can't be runtime-resynced because `#NetworkLookup.level_keys` folds into the lobby `combined_hash` (sealed pre-handshake — see "Lobby combined_hash" above).

### The pattern: host broadcasts resolved output, clients overwrite in place

1. Hook the deterministic generator at the call site that produces the divergent output (`deus_populate_graph` for CW). On host's return path, broadcast the result; on client's return path, apply the snapshot.
2. Late-arrival apply at a downstream consumer (`DeusMapScene.on_enter`) for cases where the RPC lost the race against the engine's setup RPC.
3. **In-place mutation only** — preserves table identity that the controller's internal references hold, and preserves topological fields (`next`, `layout_x/y`) that are deterministic and not shipped.
4. **Short JSON keys** to keep payload tight (`l`=level, `b`=base_level, etc.). Reuse the existing chunked-send pattern from `ct_sync_host_settings_chunk` (VMF RPC string cap is 500 chars; chunk at 400 for envelope headroom — see `reference_vmf_rpc_string_cap` rule in repo memory).
5. Forward-compat: pure `mod:network_register` string-keyed RPC. Old-mod peers silently drop the packet — no crash, no NetworkLookup writes.

### When NOT to use

If the divergent state can be host-synced via the existing settings broadcast (toggle doesn't affect lobby_hash) — do that instead. The graph-snapshot RPC is only needed when the *driving toggle itself* can't be host-synced.

### Implementation reference

`chaos_wastes_tweaker.lua` v0.7.64:
- `GRAPH_FIELD_MAP` (short-key map for wire shape)
- `apply_graph_snapshot`, `broadcast_graph_snapshot`
- `mod:network_register("ct_graph_snapshot_chunk", ...)` — mirrors existing `ct_sync_host_settings_chunk` pattern
- Two apply sites: post-`deus_populate_graph` (common) + `DeusMapScene.on_enter` (late-arrival re-apply)

**Host-migration is NOT covered** — the new host's snapshot represents its pre-migration state. Document as known limit; revisit only if visible drift after migration is reported.

## Adventure pool duplicate aliases and the network level budget

`NetworkLookup.level_keys` is bounded by `Network.type_info("weight_array").max_size` during `scripts/network_lookup/network_constants.lua`. In the 2026 yearly-events build the fixed limit is 1,024 and the vanilla prefix observed before CT injection is 582. CT's static catalog currently costs `35 missions x 6 themes = 210`, leaving 232 keys of headroom.

Pool-floor `_dupN` entries are solver identities, not new playable levels. Do not clone them into `LevelSettings` or register them in `NetworkLookup.level_keys`. Put their fully composed keys in the current journey's `config.LEVEL_ALIAS` instead:

`ground_zero_dup1_belakor_path1 -> ground_zero_belakor_path1`

Vanilla `deus_populate_graph.lua:1096-1099` applies this alias after graph placement and before the node leaves the generator, preserving the chosen source mission, theme, and path without spending a network key. `qa/check_level_lookup_budget.ps1` is a blocking Quick/full QA and publish gate. It must be updated deliberately if a future VT2 executable changes the logged vanilla prefix or the engine array capacity.
