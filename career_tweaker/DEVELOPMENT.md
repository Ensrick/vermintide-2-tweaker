# Career Tweaker — Development Notes

Internal id `crt`, Workshop 3716286199, single-stream **public** (edit this
directory directly; ships with `-AllowPublic`). The 0.4.0 beta contains opt-in
career reworks; the experimental talent/ability casting-transposition system is
intentionally excluded. Lua-only (survives hot-reload in theory, but full
restart is still safest).

Public-beta boundary check: `pwsh career_tweaker/tests/check_public_beta.ps1`.
It fails if casting/transposition widgets/loaders or the #440 co-op probe
return, if the read-only #221 ownership census is absent, or if the matching
runtime contracts disappear.

> Operational rules live in the repo-root `PROJECT_STANDARDS.md` (esp. §2.2a
> module-split conventions and §3.6 logging). This file is the crt-specific
> technical map: the module contracts and where new code goes so the entry file
> does not regrow.

## Overview

`crt` was a single monolith (`career_tweaker.lua`, 1332 lines). As of
**v0.3.57-dev** the entry is decomposed per the §2.2a template: the entry is a
manifest + lifecycle surface, and each concern lives in a single-responsibility
module. The mod already carried several concern files (balance, tourney,
armor/overcharge, oe_cooldown, mutex); Phase 1 (v0.3.57-dev) added the three
`_crt_*` modules below.

## The `mod._crt` shared namespace

Every active module and the entry's lifecycle callbacks communicate through one
table, `mod._crt` (created at the top of `career_tweaker.lua`). A module that owns a
function exports it through that table;
consumers read it. Cross-module reads that happen at LOAD time (e.g. the
regression module capturing `mod._crt.balance` as a file-local) require the owner
to be EARLIER in the manifest; reads that happen at RUNTIME (lifecycle callbacks,
hook bodies, the `/crt_regression_test` command) do not care about load order,
because the field is populated by the time the player triggers them.

Established mod fields that predate the namespace stay as-is:
`mod._crt_registered_buff_names`, `mod._crt_mod_registered_buff_names`,
`mod._crt_peer_parity`, `mod._crt_hellborgs_crit_hook_installed`,
`mod._crt_oe_cdr_tick`, `mod._crt_auto_dump_check`, etc.
(The `mod._crt_parity_settled_enabled` mirror flag was removed in v0.3.58-dev,
issue 506: the apply engines now read `mod._crt_peer_parity:applied_state()`
directly since the shared lib commits `_applied` before firing gate callbacks.)

## Module map (v0.3.57-dev)

Manifest = the `mod:dofile` order in `career_tweaker.lua`. Data files
(`_data` / `_localization`) load before the script per VMF (localization → data
→ script), so script-set fields are nil when they evaluate.

| File | Responsibility | Public surface (via `mod._crt` unless noted) | Manifest position |
|------|----------------|----------------------------------------------|-------------------|
| `career_tweaker.lua` | Entry/manifest + lifecycle. MOD_VERSION, boot banner/fingerprint, the dofile manifest, the mutex cluster declare, Character-XP-level override + Unlock-All-Careers hooks, `mod.update`, `on_game_state_changed` / `on_setting_changed` / `on_disabled`, `ct_status`, the issue-425/#776 exact-catalog beacon, and the public-beta exclusion markers. | owns `mod._crt`, `mod._crt.MOD_VERSION`, `mod._crt.dbg` / `dbg_alert`, `mod._crt.balance`, `mod._crt_peer_parity`, `wire_catalog_identity` | — (the entry) |
| `career_tweaker_data.lua` | VMF widget tree (the settings UI). | returns the widget table | before script (VMF) |
| `career_tweaker_localization.lua` | Localized strings. | returns the loc table | before data (VMF) |
| `_crt_damage_classification.lua` | Pure #334/#472 damage-category policy: chip/AOE, self-DoT, and Focused Spirit's Ratling extension. Engine-free and unit-tested. | returns `{ is_chip_or_aoe, is_self_dot, focused_spirit_ignores }`, published as `mod._crt.damage_classification` | first script module, before balance |
| `_crt_wire_policy.lua` | Pure #776 exact name+numeric-index fingerprint, `rpc_add_buff` receiver decision, and one-stack timed-effect policy. Engine-free and unit-tested. | `mod._crt.wire_policy`; returns catalog identity, duration validator, timed-buff builder/refresh semantics | after damage classification, before balance |
| `_crt_wire_runtime.lua` | #776 engine adapter for parity-gated `LocalAndServer` timed buff emission. | `ensure_timed_proc`; owns the sole `add_buff_synced` call and bounded route logs | loaded by `career_tweaker_balance.lua`; no hooks |
| `career_tweaker_balance.lua` | The BALANCE_MODS rework catalog + apply/restore engine, crt_* buff pre-registration, and issue-425/#776 parity/wire-safe proc wrappers. It loads the hook module once after constructing the catalogue. | returns `{ apply, restore, active_count, parity_gate_ok, wire_parity_live, network_unsafe_ids, BALANCE_MODS }`; sets `mod._crt_registered_buff_names`, `mod._crt_mod_registered_buff_names` | after the pure policies (entry captures `balance`) |
| `_career_tweaker_balance_hooks.lua` | Hook-only boundary extracted from the balance catalogue: per-career `no_random_crits`, Hellborg crit penalty, centralized rework-description `Localize`, the #776 `rpc_add_buff` receiver floor, and the issue-425 hot-join replay filter. It owns no catalogue or apply/restore state. | installs five hooks; preserves `mod._crt_hellborgs_crit_hook_installed`; sets `_crt_rpc_add_buff_floor_installed` | dofile'd exactly once by `career_tweaker_balance.lua` |
| Big Rebalance (retired) | The unreachable port was deleted in 0.3.70-dev (#433). Recover historical source from git only as part of a new registration/parity design. | none | absent |
| `career_tweaker_tourney.lua` | Tourney Balance Testing port (`trn_*` toggles). Same `{apply,restore,active_count}` contract. | returns the contract table | after balance |
| `_crt_rework_master_policy.lua` | Engine-free #445 family-master planner plus the canonical authorship-prefix metadata shared by runtime, localization, and QA. | returns `{ new, family_for_setting, is_leaf_localization_key, decorate_label, FAMILIES }`; runtime publishes the module and policy as `mod._crt.rework_master_module` / `.rework_master_policy` | after balance and tourney; required independently by localization before script load |
| `_crt_foot_knight_policy.lua` | Engine-free #619 capability, enemy-category, Final March, and secondary-slot composition policy. Shield/great-weapon behavior is template-capability based so compatible WT/CWV templates inherit it. | returns `{ is_shield_type, is_non_polearm_great_type, plan_secondary_slot, all_other_allies_dead, enemy_multiplier }`; published as `mod._crt.foot_knight.policy` | loaded by `_crt_foot_knight.lua` |
| `_crt_foot_knight.lua` | Bounded #619 Foot Knight runtime. Owns local-only buff templates, 0.2s state reconciliation, once-per-mission Final March, Teamwork proximity state, reversible Teamwork range, and the native secondary-melee slot-map mutation. | `mod._crt.foot_knight = { tick, apply_settings, restore, reset_mission_state, outgoing_damage_multiplier, policy, setting_ids }` | after tourney and before armor/overcharge |
| `career_tweaker_armor_overcharge.lua` | Seven armor/overcharge/Focused-Spirit controls using one `DamageUtils.apply_buffs_to_damage` hook and one consolidated `PlayerUnitHealthExtension.add_damage` hook. Owns Focused Spirit's proc wrapper and one-frame cooldown re-arm; the stacking template fields remain in balance's reversible lifecycle. | installs its own hooks; exports `mod._crt_focused_spirit_tick(dt)` | after tourney |
| `career_tweaker_oe_cooldown.lua` | Outcast Engineer cooldown-reduction benefit. Driven per-frame from the entry's `mod.update`. | `mod._crt_oe_cdr_tick(dt)`, `mod._crt_oe_cdr_clear` | after armor |
| `career_tweaker_mutex.lua` | Mutex cluster framework ("pick one of N" checkbox groups), enforced from `on_setting_changed`. | returns `{ declare, enforce, active, snapshot }` | after oe |
| `_crt_talent_selection.lua` | Pure snapshot/equality policy for the independent no-op talent-menu close guard (#283). | returns `{ snapshot, equal }`, published as `mod._crt.talent_selection` by the guard | loaded by `_crt_talent_menu_guard.lua` |
| `_crt_talent_menu_guard.lua` | Desktop/controller talent-picker lifecycle guard. Skips only an identical close so live accumulated talent buffs are not rebuilt; changed or invalid selections delegate to vanilla. | sets `talent_menu_guard_installed`; installs four bounded hooks | after the public-beta swap exclusion, before diagnostics |
| `_crt_talent_swap.lua` | Dormant historical talent-tree + ability/passive swap engine. Saved `talent_swap_*` values remain in VMF storage, but the beta exposes no widgets and never loads this module. | none in the beta | **not loaded in the beta line** |
| `_crt_diagnostics.lua` | Read-only talent/buff diagnostics: `/crt_dump_talents`, the reusable dump body, the per-session auto-dump harness + retry pump. | `mod.crt_dump_career_talents` (mod method), `mod._crt_auto_dump_check`, `mod._crt_dump_retry_tick(dt)`, `mod._crt_start_dump_retry` | after talent |
| `_crt_bardin_disabler_probe.lua` | Dormant #440 comparison probe retained for a future diagnostic build. | none in the beta | **not loaded in the beta line** |
| `_crt_umbrella_audit_policy.lua` | Read-only #221 ownership census for the deferred subgroup-master boundary. It counts the live native/Tourney catalogs and the cross-owner Unchained, Engineer, and armor clusters without writing settings or installing hooks. | `mod._crt.umbrella_audit_policy`; `mod._crt.umbrella_audit()`; `/crt_umbrella_audit` | after the #445 policy, before master callbacks |
| `_lib_peer_parity.lua` | COPIED single-source shared lib (master: `tools/shared_lib/_lib_peer_parity.lua`). The issue-371 peer-parity beacon factory. Do NOT diverge from master. | returns a factory function | dofile'd inside the beacon block |
| `_crt_regression.lua` | The `/crt_regression_test` harness + all check bodies, in frozen registration order. | `mod._crt.rt_register` (for future phases) | LAST |

## Where new code goes

1. **A redesigned talent/ability casting-transposition concern** → work behind
   the public-beta exclusion first. Do not restore the widget group or load
   `_crt_talent_swap.lua` until its identity/lifecycle design has deterministic
   tests and explicit user approval for a later beta.
2. **A new rework / balance tweak** → `career_tweaker_balance.lua` (BALANCE_MODS).
   Declarative `patches` target `BuffTemplates[name].buffs[sub_index or 1]`;
   specify `sub_index` when a parent template contains multiple sub-buffs (#366).
   If it reaches a vanilla NETWORKED buff path, it MUST route through a
   `crt_wire_safe_*` wrapper and carry `network_unsafe = true`, and its buff
   names go in the alphabetically-sorted `_CRT_BUFF_NAMES` (the sort assigns the
   NetworkLookup indices every peer must agree on). Then add the name to
   `_CRT_BUFF_NAMES_EXPECTED` in `_crt_regression.lua` and, if it is
   `network_unsafe`, to `_CRT_NETWORK_UNSAFE_EXPECTED` there too - the catalog
   parity checks fail loudly if the two sides drift.
   Rework talent text belongs in `_career_tweaker_balance_hooks.lua`'s
   `CRT_DESC_OVERRIDES`; extend its existing `_G.Localize` hook rather than
   registering another one. A new crit or hot-join policy must likewise merge
   into that module's existing hook for the same target.
3. **A new diagnostic / dump command** → `_crt_diagnostics.lua`.
4. **A new regression check** → `_crt_regression.lua`. Register with `_rt_register`
   in the intended output position (registration order = in-game print order,
   frozen surface - appending is safe, reordering is not). If the check probes a
   file-local of another module, add a minimal `mod._crt` accessor in that module
   rather than reaching across files.
5. **A new lifecycle need** (something that must run at boot, on state change, on
   setting change, on disable, or per-frame) → wire the call into the matching
   callback in the entry, delegating into the owning module. There is exactly ONE
   `mod.update`; add per-frame work as a `mod._crt_*_tick(dt)` in a module and
   call it from the entry's `mod.update` (guarded), next to the OE and dump ticks.
6. **A new hook** → grep every crt file for the `(Class, method)` FIRST (VMF
   silently drops the 2nd hook on a pair). Put the hook in the module that owns
   the behavior. Add a `/crt_regression_test` target-present check for it.

## Ranger ale action-speed contract (#367)

The ale's live action remains the vanilla `bardin_survival_ale.actions.action_one.default`
shape with `total_time = 1.9` [src:
`scripts/settings/equipment/weapon_templates/bardin_survival_ale.lua:5-23`]. The
opt-in rework changes only `anim_time_scale`, deriving it as `1.9 / 0.75`.
`WeaponUnitExtension.start_action` divides `total_time` by the action scale and
passes the corresponding animation scale to both third-person and first-person
playback [src:
`scripts/unit_extensions/weapons/weapon_unit_extension.lua:486-489,580-600`].
Keep the stock duration canonical, preserve the `one_time_consumable` path, and
restore either the exact prior scale or exact nil absence. Coverage lives in
`qa/lua/tests/test_crt_ale_animation.lua` and runtime check
`issue367_ale_one_second_drink`; that historical registered name stays stable
even though its assertion now targets 0.75 seconds.

## Foot Knight #619 authority and compatibility

- The custom buff templates are process-local and deliberately absent from `NetworkLookup`. On the host, the runtime reconciles every human and bot unit because damage and bot behavior are authoritative there. On clients, it reconciles only the local player for movement and combat prediction. No vanilla RPC carries a custom identifier.
- Rock's dodge drawback composes through vanilla's `apply_movement_buff`/`remove_movement_buff` distance path. Teamwork cancels exactly the native -0.10 `damage_taken` contribution with a +0.10 local stat buff only while that native buff exists; it does not rewrite the aura, talent stacks, or Final March.
- WT/CWV interoperability is capability-based: live `weapon_type`, runtime template name, and inherited melee template metadata decide behavior. Avoid item-key allowlists.
- Secondary melee reconciles both canonical live carriers: backend validation reads `CareerSettings.es_knight.item_slot_types_by_slot_name.slot_ranged`, while inventory category creation reads the Foot Knight career object under `SPProfiles`. Stock aliases them, but CRT handles independent replacement, preserves each array identity, keeps both `melee` and `ranged` accepted while enabled, and never deletes an inventory item.
- Buff-bar state is carried by the existing stable local-only effect buffs, never by the 0.2s tick itself. Icons reuse the exact authored vanilla Foot Knight talent art: both Rock effects use Rock of Reikland, Teamwork uses That's Bloody Teamwork, and the other effects retain their matching Foot Knight keys. Rock/Teamwork conditional buffs retain their IDs until the condition changes, Final March puts one icon on its power sub-buff, and the internal Teamwork DR canceller intentionally has none. While #699 is open, the transition-only `[crt:699]` census records the live template icon, atlas residency, vanilla BuffUI widget result, active count and total pool capacity, and stock HideBuffs disposition; it never mutates presentation state. Its subject selection mirrors `BuffUI._sync_buffs`: local player normally, `_spectated_player_unit` while spectating, including host-side bot verification.

## Load-order rules that are load-bearing

- **`_crt_regression.lua` is LAST.** Its check bodies capture `mod._crt.balance`,
  the `_dbg` helpers, and `MOD_VERSION` as module-locals at load. It also asserts
  that the beta exclusion markers are present and the retired runtime exports
  remain nil.
- **`_crt_talent_swap.lua` is deliberately absent from the manifest.** Its
  casting/transposition exports and mutation lifecycle remain excluded. The
  independent `_crt_talent_menu_guard.lua` owns the only active talent-window
  hooks and does not read or expose any `talent_swap_*` state.
- **The issue-425 beacon block sits AFTER `mod.update` is defined.** The shared
  lib's `install()` WRAPS the existing `mod.update`; running it earlier would
  capture nil and drop the OE + dump ticks.
- **Big Rebalance has no script module or lifecycle stub.** Old `cbr_*` saved
  values are preserved but unread. The prefix remains reserved by the blocking
  retirement gate; revival starts from git history under a new architecture.

## Issue-425/#776 wire safety (why emission stays in balance)

The cross-peer wire-safety subsystem (a missing or differently-indexed peer can
CTD on `rpc_add_buff` decode of a modded buff index) keeps its emission guards
in balance. The
`network_unsafe = true` tags live on individual BALANCE_MODS rework definitions
throughout the file, and `_crt_parity_gate_ok` / `_crt_wire_parity_live` are
consumed by the core `apply_balance_mods` engine (which owns the data) as well as
exported for the beacon callbacks and the regression suite. Splitting only the
wrapper functions would leave the tags and the consuming engine in balance while
the wrappers live elsewhere, forcing bidirectional `mod._crt` plumbing that
increases coupling. Full mechanic + the five-gate model:
`chaos_wastes_tweaker_dev/ENGINE_SURFACE.md` (issue 426 beacon) and the crt
`REGRESSION_CHECKLIST.md` "crt-networked-rework-peer-parity" row.

Issue #776 proved that presence is not catalog parity: three client crashes all
decoded host numeric id `1574` as timed Impetuous AS while carrying positive
server ids, even though the Impetuous proc itself only used the server-id-zero
path. The entry therefore fingerprints every registered CRT name together with
its live numeric lookup id. The shared beacon accepts only an exact identity.
CRT supplies that identity through `_crt_wire_runtime.wrap_parity_transport`;
the copied shared library itself remains byte-identical for every consumer.
The hook module owns the complementary receiver floor because an unrelated old
host can emit a colliding id before/without a safe CRT sender path. Never remove
either layer, replace the exact identity with version-only presence, or fall
back from timed `LocalAndServer` sync to generic `ProcFunctions.add_buff`.
