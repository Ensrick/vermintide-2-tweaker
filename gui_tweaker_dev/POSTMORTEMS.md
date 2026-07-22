# Tweaker: GUI postmortems

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
