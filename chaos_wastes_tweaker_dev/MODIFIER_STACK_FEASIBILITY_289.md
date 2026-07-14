# Multiple Chaos Wastes Modifiers (#289)

Status: diagnostics armed; co-op evidence required; activation remains disabled.

## Source boundary

Vanilla already composes several modifiers into one mission list. `DeusMechanism`
adds the current node's single `curse`, every entry in `minor_modifier_group`, and
theme mutators (`deus_mechanism.lua:781-799`). `GameModeDeus.mutators` also appends
the run's event-mutator list while deduplicating names
(`game_mode_deus.lua:667-683`). `MutatorHandler` initializes and activates every
entry (`mutator_handler.lua:85-111`) and hot-join syncs every active mutator
(`mutator_handler.lua:148-166`).

The limiting boundary is therefore not the handler's count. The expedition graph
serializes one `node.curse`; its nearby minor modifiers are already a list. Run
event mutators are also a list and preload each template's declared packages
(`deus_run_state.lua:438-461`), but using that channel for extra curses would need
compatibility proof for curse UI, rewards, objective ownership, cleanup, and
host/client parity. Replacing `node.curse` with a table would violate vanilla's
graph and UI contract.

## Armed audit

`_ct_modifier_stack_audit.lua` observes only. On mission entry and on
`/ct_modifier_stack_audit`, it prints bounded `[ct:289]` rows containing:

- host/client role and completed-level count;
- the proposed bounded ramp target (1 initially, 2 after two completed levels,
  3 after four);
- counts for the singular node curse, minor modifiers, and event modifiers;
- deterministic signatures for the effective and active lists;
- declared package, missing-template, missing-wire, and duplicate counts.

No graph field, mutator list, package, lookup, RPC, or setting is changed.

## Decision gate

Capture the same mission on host and client. Their `effective` and `active`
signatures must match, with zero missing templates, missing wire entries, and
duplicates. After that, test a curated pair through the existing event-mutator
list, not a widened `node.curse` field. Only pairs with clean activation, cleanup,
hot join, UI, package, and performance evidence can enter an allowlist. The ramp
must select from that allowlist and remain capped; it must not stack arbitrary
curse names.
