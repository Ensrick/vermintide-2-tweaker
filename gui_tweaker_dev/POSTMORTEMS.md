# Tweaker: GUI postmortems

## #954 - read-boundary reconciliation protected zero bot snapshots

**Symptom.** Editing the host player's saved loadout still changed a bot's
designated equipment after the detached-snapshot candidate shipped. The runtime
regression nevertheless reported PASS.

**Root cause.** The reconcile hook was live: Rain's v0.2.318-dev log repeatedly
recorded `identity_changed=true`. Every record also said `applied=0`. Native bot
assignments created before GUT's owner existed remained only in
`PlayerData.loadout_selection.bot_equipment`; the GUT store had neither
`bot_index` nor `bot_loadout`, so there was nothing to reconcile. The synthetic
regression constructed a snapshot and never proved that a live native
designation had entered the detached owner.

**Fix.** At the first eligible bounded bot read, import each native designation
whose GUT entry is still unowned. Resolve the native index against the already
seeded GUT rows, copy only canonical loadout slots, persist a durable migration
marker once, and never follow that source row again. Preserve any explicit GUT
snapshot, defer a valid index until its row exists, and leave official/read-only
realms native.

**Future prevention.** A runtime ownership check must prove non-vacuity. When
native assignments exist, zero imported snapshots is a failure, not a PASS.
Offline coverage starts from the actual legacy `PlayerData` shape, mutates the
source row after import, and proves both one-time persistence and explicit-owner
precedence. See BUG_CLASSES class 80.

## #273 - Chaos Wastes exit snapshot persisted generated Deus weapon ids

**Symptom.** A CWV weapon remained correct inside a Chaos Wastes run but reverted
to the player's prior native weapon on returning to the expedition lobby.

**Root cause.** The bounded GUT exit snapshot correctly read the live selected
loadout, but treated the Adventure mirror key as proof that every live slot was
durable. During a Deus run, `BackendUtils` dispatches melee/ranged through the
Deus interface, whose generated backend ids cease to resolve when the override
is removed. The snapshot overwrote stable GUT/CIM ids with those temporary ids.

**Fix.** Gate each slot before the live read. The active per-slot interface must
be identical to the durable `items` interface; foreign or unknown owners are
skipped without clearing the stored value. This keeps items-owned cosmetics
eligible and adds no hook, polling loop, or second writer.

**Why it recurred.** The earlier CWV fix established exact Deus item mapping
inside a run, while the exit persistence backstop was evaluated as a realm-level
feature. Those are different identity lifetimes. Issue #174 had the same visible
reversion but closed before the first divergent store write was instrumented.

**Future prevention.** BUG_CLASSES class 73 and the engine loadout reference now
require per-slot owner proof before any durable snapshot. Offline tests pin mixed
Deus ownership and gate-before-read ordering; runtime diagnostics report one
bounded `foreign_slot_reads` count per exit edge.
