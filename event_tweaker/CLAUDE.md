# CLAUDE.md — event_tweaker

Workflow guardrails for "Tweaker: Events" (internal id `event_tweaker`, Workshop
3721290755, single-stream, PUBLIC item). This file does NOT auto-load — the
monorepo hub `vermintide-2-tweaker/CLAUDE.md` routes here. It carries only the
rules specific to this mod; architecture and recipes live in `DEVELOPMENT.md`.

## Read first

1. `DEVELOPMENT.md` "File map" + "Module contracts" — the mod is split into
   single-responsibility `_evt_*` modules (v0.4.26-dev). Its "Where new code
   goes" section tells you which module owns your change. Do not grow the entry
   file back into a monolith.
2. `REGRESSION_CHECKLIST.md` — walk the et slugs before any release that touches
   the relevant subsystem; the runtime twin is `/event_tweaker_regression_test`.

## Hard rules (beyond the repo-wide NON-NEGOTIABLES)

- **Issue guards are load-bearing.** `_evt_guard413_weave.lua` (stock weave-only
  mutators CTD vanilla clients; Shadow's only exception is the capability-gated,
  asset-free `_evt_shadow_adventure.lua` adapter), `_evt_guard455_boss_events.lua` (boss_events-less
  levels host-fatal), `_evt_guard386_pacing.lua` (scalar pacing kills
  ConflictDirector). Never remove, weaken, or toggle-gate them; their regression
  checks and checklist slugs must survive every refactor.
- **All injection funnels through `add()`** in `_evt_selection.lua`'s
  `gather_mutators()`. A new injection route that bypasses it silently bypasses
  the guards — that is how vanilla clients crash.
- **Catalog data is single-source.** Mutators/presets/DLC maps live ONLY in
  `event_tweaker_catalog.lua`; curse data ONLY in `event_tweaker_curses.lua`.
  Both are require'd modules because script-set `mod._fields` are nil when
  `_data.lua`/`_localization.lua` evaluate. Never duplicate them "locally".
- **Manifest discipline.** Modules are `mod:dofile`'d exactly once, from the
  entry manifest, in dependency order; `mod:dofile` is not a singleton, so
  modules never dofile each other. Cross-module surface goes through `mod._evt`.
- **One hook per (Class, method) mod-wide.** Currently 17 hooks across
  `_evt_backend_hooks` / `_evt_guard386_pacing` / `_evt_diagnostics` /
  `_evt_cursed_adventure` / `_evt_preview` / `_evt_missions` (the four
  desktop/controller area/mission-menu hooks, issue 626; plus the two `IngamePlayerListUI`
  `_setup_deed_reward_data` + `_draw` hooks, issue 532) — grep all `_evt_*` files
  before adding any hook.
  `_evt_guard430_curse_parity` owns the singleton `GameModeBase.is_joinable`
  wrapper for its pre-game-session hot-join lock. Its peer-parity beacon polls
  the player roster and OWNS `mod.update` via the shared lib's
  `install()`, which wraps any pre-existing `mod.update`. event_tweaker defines
  none of its own, so nothing else may set `mod.update` or it clobbers the beacon
  tick — drive per-frame work through the beacon instead.
- **Ship**: `-dev` version = full pipeline every build, no ask, and the item is
  public, so always `tools\ship\ship.ps1 -Mod event_tweaker -AllowPublic`; then
  git add (new files explicitly) + commit + push in the same pass.

## What makes this mod different

Host-side injection into the live-events backend: most features need ONLY the
host modded (vanilla clients receive mutators via `rpc_activate_mutator_client`),
  EXCEPT the Cursed Adventure group and Adventure Shadow, which need every peer
  to run the required capability (curse packages; Shadow's safe template adapter).
  Consequence:
anything you inject is broadcast to unmodded peers — crash safety of injected
names is THIS mod's core invariant, which is why the guards above exist.
