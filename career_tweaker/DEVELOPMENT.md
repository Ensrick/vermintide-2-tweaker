# Career Tweaker — Development Notes

Internal id `crt`, Workshop 3716286199, single-stream **public** (edit this
directory directly; ships with `-AllowPublic`). Talent/ability swapping plus a
set of opt-in career reworks. Lua-only (survives hot-reload in theory, but full
restart is still safest).

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

Every module and the entry's lifecycle callbacks communicate through one table,
`mod._crt` (created at the top of `career_tweaker.lua`). A module that owns a
function EXPORTS it (`mod._crt.apply_talent_swaps = apply_talent_swaps`);
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
| `career_tweaker.lua` | Entry/manifest + lifecycle. MOD_VERSION, boot banner/fingerprint, the dofile manifest, the mutex cluster declare, the Character-XP-level override + Unlock-All-Careers hooks, the 2026-06-21 ability-swap / career-select bug-fix hooks, `mod.update`, `on_game_state_changed` / `on_setting_changed` / `on_disabled`, `ct_status`, and the issue-425 beacon install. | owns `mod._crt`, `mod._crt.MOD_VERSION`, `mod._crt.dbg` / `dbg_alert`, `mod._crt.balance`, `mod._crt_peer_parity` | — (the entry) |
| `career_tweaker_data.lua` | VMF widget tree (the settings UI). | returns the widget table | before script (VMF) |
| `career_tweaker_localization.lua` | Localized strings. | returns the loc table | before data (VMF) |
| `_crt_damage_classification.lua` | Pure #334/#472 damage-category policy: chip/AOE, self-DoT, and Focused Spirit's Ratling extension. Engine-free and unit-tested. | returns `{ is_chip_or_aoe, is_self_dot, focused_spirit_ignores }`, published as `mod._crt.damage_classification` | first script module, before balance |
| `career_tweaker_balance.lua` | The BALANCE_MODS rework catalog + apply/restore engine, the crt_* buff pre-registration, AND the issue-425 wire-safety subsystem (parity gate, wire-safe proc/driver wrappers, hot-join replay filter). | returns `{ apply, restore, active_count, parity_gate_ok, wire_parity_live, network_unsafe_ids, BALANCE_MODS }`; sets `mod._crt_registered_buff_names`, `mod._crt_mod_registered_buff_names` | after damage classification (entry captures `balance`) |
| `career_tweaker_big_rebalance.lua` | Big Rebalance port. **ON ICE** (bt retired 2026-06-08): not dofile'd; a stub honors the `{apply,restore,active_count}` contract in the entry. | (dormant) | not loaded |
| `career_tweaker_tourney.lua` | Tourney Balance Testing port (`trn_*` toggles). Same `{apply,restore,active_count}` contract. | returns the contract table | after balance |
| `career_tweaker_armor_overcharge.lua` | Seven armor/overcharge/Focused-Spirit controls using one `DamageUtils.apply_buffs_to_damage` hook and one consolidated `PlayerUnitHealthExtension.add_damage` hook. Owns Focused Spirit's proc wrapper and one-frame cooldown re-arm; the stacking template fields remain in balance's reversible lifecycle. | installs its own hooks; exports `mod._crt_focused_spirit_tick(dt)` | after tourney |
| `career_tweaker_oe_cooldown.lua` | Outcast Engineer cooldown-reduction benefit. Driven per-frame from the entry's `mod.update`. | `mod._crt_oe_cdr_tick(dt)`, `mod._crt_oe_cdr_clear` | after armor |
| `career_tweaker_mutex.lua` | Mutex cluster framework ("pick one of N" checkbox groups), enforced from `on_setting_changed`. | returns `{ declare, enforce, active, snapshot }` | after oe |
| `_crt_talent_selection.lua` | Pure snapshot/equality policy for the desktop and controller talent-menu no-op guard (#283). Engine-free and unit-tested. | returns `{ snapshot, equal }`, published as `mod._crt.talent_selection` | loaded by `_crt_talent_swap.lua` |
| `_crt_talent_swap.lua` | Talent-tree + ability/passive swap engine: desktop/controller talent-window lifecycle hooks, no-op close guard, DLC gate, apply/restore. | `apply_talent_swaps`, `restore_talent_swaps`, `refresh_talent_ui`, `ALL_CAREERS`, `get_talent_swap_originals` / `set_talent_swap_originals`; sets `talent_menu_guard_installed` | after mutex, before the entry captures its talent lifecycle locals |
| `_crt_diagnostics.lua` | Read-only talent/buff diagnostics: `/crt_dump_talents`, the reusable dump body, the per-session auto-dump harness + retry pump. | `mod.crt_dump_career_talents` (mod method), `mod._crt_auto_dump_check`, `mod._crt_dump_retry_tick(dt)`, `mod._crt_start_dump_retry` | after talent |
| `_lib_peer_parity.lua` | COPIED single-source shared lib (master: `tools/shared_lib/_lib_peer_parity.lua`). The issue-371 peer-parity beacon factory. Do NOT diverge from master. | returns a factory function | dofile'd inside the beacon block |
| `_crt_regression.lua` | The `/crt_regression_test` harness + all check bodies, in frozen registration order. | `mod._crt.rt_register` (for future phases) | LAST |

## Where new code goes

1. **A new talent/ability swap concern** → `_crt_talent_swap.lua`. If the entry's
   lifecycle callbacks must drive it, export through `mod._crt` and capture a
   file-local in the entry right after the talent dofile (mirror the existing
   `apply_talent_swaps` capture).
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

## Load-order rules that are load-bearing

- **`_crt_regression.lua` is LAST.** Its check bodies capture `mod._crt.balance`,
  the talent-swap restore path + accessors, the `_dbg` helpers, and `MOD_VERSION`
  as module-locals AT LOAD. Those must be populated first (balance dofile,
  talent dofile, and the entry's top-of-file exports).
- **`_crt_talent_swap.lua` loads before the entry captures its talent lifecycle
  locals** (`apply_talent_swaps` etc.), because the lifecycle callbacks call the
  captured file-locals.
- **The issue-425 beacon block sits AFTER `mod.update` is defined.** The shared
  lib's `install()` WRAPS the existing `mod.update`; running it earlier would
  capture nil and drop the OE + dump ticks.
- **`career_tweaker_big_rebalance.lua` is not loaded** (bt retired); the entry
  substitutes a `{apply,restore,active_count}` stub. To revive: restore bt,
  delete the stub, un-comment the dofile.

## Issue-425 wire safety (why it stays in balance)

The cross-peer wire-safety subsystem (a non-crt peer CTDs on `rpc_add_buff`
decode of a modded buff index) is deliberately NOT split out. The
`network_unsafe = true` tags live on individual BALANCE_MODS rework definitions
throughout the file, and `_crt_parity_gate_ok` / `_crt_wire_parity_live` are
consumed by the core `apply_balance_mods` engine (which owns the data) as well as
exported for the beacon callbacks and the regression suite. Splitting only the
wrapper functions would leave the tags and the consuming engine in balance while
the wrappers live elsewhere, forcing bidirectional `mod._crt` plumbing that
increases coupling. Full mechanic + the five-gate model:
`chaos_wastes_tweaker_dev/ENGINE_SURFACE.md` (issue 426 beacon) and the crt
`REGRESSION_CHECKLIST.md` "crt-networked-rework-peer-parity" row.
