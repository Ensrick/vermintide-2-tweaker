# Multiple Chaos Wastes Modifiers (#289)

Status: bounded two-modifier proof implemented default-off in 0.7.351-dev
(host-authoritative, curated pair through the composed mission list); awaiting
in-game verification. The 1/2/3 ramp beyond the proof stays closed.

## Implemented proof (0.7.351-dev)

`_ct_progressive_modifier_runtime.lua` owns the single CT hook on
`GameModeDeus.mutators`, the vanilla seam that folds the node curse, minor
modifiers, theme/node mutators, live-event mutators and the run's event-mutator
list into one mission list (`game_mode_deus.lua:667-686`;
`deus_mechanism.lua:781-808`). `GameModeManager` reads it once per mission to
build the `MutatorHandler` (`game_mode_manager.lua:85-99`). Vanilla runs first;
host-only, and only when the option is on, the hook appends ONE extra from the
curated pair `curse_empathy` / `curse_abundance_of_life` once two levels are
completed (the documented ladder's second step). The node's singular `curse`
field is never written, so the map, curse panel, reward and objective contracts
that read it are unchanged.

Why this pair: both are vanilla Chaos Wastes pool curses
(`deus_map_populate_settings.lua:19-23`), both declare no `packages`
(`mutator_curse_empathy.lua:273-276`; `mutator_curse_abundance_of_life.lua:3-6`),
neither spawns units, changes lighting/shading (#104) or owns an objective, and
both are vanilla `NetworkLookup.mutator_templates` entries
(`network_lookup.lua:266`). `curse_monophobia` is package-free too but is not in
the vanilla pool, so it is not curated. The selector additionally rejects a
curse the host disabled (CT's `_activate_mutator` gate would otherwise leave it
initialized but never activated) and any live template that declares packages.

Transport is vanilla: host initialize/activate of every list entry
(`mutator_handler.lua:45-48,85-111`), `rpc_activate_mutator_client` keyed by the
vanilla lookup (`:697-702`), shared-state initialized map (`:95-99,795-797`),
hot-join replay of every active mutator (`:148-170`;
`game_mode_manager.lua:920`), teardown deactivation (`:60-83`). Clients never
consult their own composed list (`:49-55`), so the hook is inert there. The
earlier client capture `effective=5 active=0` came from the automatic
`StateIngame` row, which fires before those activation RPCs land; the
mid-mission `/ct_modifier_stack_audit` command is the parity evidence.

Falsifiers still open for the live test: client `active` signature differing
from the host's, an `unexpected_active` entry outside the pair, hot-join or
next-node residue, a curse-panel/reward break, a duplicate activation fassert,
or an unacceptable frame cost while both beam curses run together.

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

Capture the same mission on host and client with the option on from map three.
Their `active` signatures must match, `unexpected_active` must be one allowlist
entry on the client and zero on the host, with zero missing templates, missing
wire entries, and duplicates. Only pairs with clean activation, cleanup, hot
join, UI, package, and performance evidence stay in the allowlist. Any wider
ramp must select from that allowlist and remain capped; it must not stack
arbitrary curse names and must never widen `node.curse` into a table.
