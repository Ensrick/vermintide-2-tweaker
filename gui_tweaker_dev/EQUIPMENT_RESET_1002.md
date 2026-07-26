# Equipment DEFAULT Lua-heap crash (#1002)

## Evidence boundary

Issue #1002 reports an out-of-memory crash after confirming DEFAULT on Mod
Tweaker's Equipment tab and attaches
`console-2026-07-23-03.04.34-8a08503c-5852-41d2-a1c4-21ad0cfab276.log`.
The attachment URL was not downloadable from the managed implementation
environment, so this note makes no claims about lines inside that log.

The source boundary is reproducible offline:

- `_mod_tweaker_view.lua` and `_mod_tweaker_state.lua` partition Equipment
  pending values by the node's real owner.
- `_mod_tweaker_transaction.lua` uses silent writes plus one completion
  callback only when that owner defines `on_settings_batch_changed`.
- Before this change, Enemy Tweaker was the only owner implementing that
  callback. Cosmetics, both CIM aliases, both WT aliases, and CWV all used the
  synchronous per-setting fallback.
- WT's ordinary `unlock_*` callback runs `apply_weapon_unlocks`,
  `patch_career_actions_on_weapons`, energy seeding, and backend refresh for
  every changed unlock.

This is the same mechanism class as verified issue #560, but across a synthetic
multi-owner tab. #560 established that repeated whole-mod setting callbacks can
exhaust the Lua heap and that silent persistence followed by one owner apply is
safe for an owner that explicitly implements the contract.

## Implemented candidate

All four Equipment owner families now opt in, including both stable/dev aliases
for CIM and WT. Each owner persists N values and
performs at most one of each owned side effect. WT reconciles both master
families before one final availability/action rebuild:

- a master-only edit still cascades to its children;
- a complete DEFAULT/profile snapshot preserves each child's committed value
  and derives the master indicator;
- `[wt:1002]`, `[cos:1002]`, `[cim:1002]`, `[cwv:1002]`, and the existing
  `[gut:560]` completion records expose the bound without per-setting spam.
- The Cosmetics completion replays setting-owned side effects only. It does not
  load, unload, adopt, or release package references; issue #565 remains the
  separate owner of asynchronous offhand-preload residency and refcount
  lifecycle.

Offline Lua 5.1 coverage proves ten values across four active owners produce
ten silent writes and four completion notifications, plus both WT master cases.
It also proves failed writes/callbacks remain retryable instead of being
silently cleared or captured as a partial profile, and a profile switch cannot
cross an incomplete pending transaction.

## Three evidence-triggered fallbacks

1. **WT work is still repeated.** Trigger: one Equipment Apply logs more than
   one WT completion or more than one availability/action apply. Change:
   instrument the named WT apply functions with a single transaction-scoped
   counter and move any missed caller behind the existing owner completion.
   Falsifier: exactly one completion and one apply of each kind, with no heap
   failure.
2. **One owner needs per-setting semantic callbacks.** Trigger: values persist
   but an owner-specific live result is stale after the batch. Change: add an
   owner-local begin/end deferral adapter that replays its existing setting-id
   branches while accumulating side effects, then flushes each side effect
   once. Falsifier: the stale result reproduces even when the ordinary branch
   is replayed once and its final apply succeeds.
3. **Writes themselves retain excessive heap.** Trigger: callback counts are
   bounded but retained Lua heap still grows materially across repeated resets.
   Change: serialize the active owner transactions over bounded frames, retain
   uncommitted buffers on failure, and record pre/post/full-GC heap once per
   owner. Falsifier: retained heap is flat across repeated resets while the
   crash remains.

## Lifecycle recommendation

Keep #1002 at `not-started` until the source commit is merged and the exact
versions of every changed owner are built, deployed, and uploaded. Then add
`verify-fix` (solo; no peer is needed) with the steps in
`REGRESSION_CHECKLIST.md`. Do not add `diagnostics-armed`, `coop-required`, or
`Fixed` before that artifact boundary.
