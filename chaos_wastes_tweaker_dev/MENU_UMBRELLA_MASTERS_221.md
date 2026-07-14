# Issue #221: Menu umbrella masters

## Historical-plan audit

The old `MENU_CONSOLIDATION_PLAN` mixed three independent mods and two different meanings of "master": an entry-point behavior gate and a bulk preset that rewrites child settings.

- General Tweaker's bot-behavior master already shipped under #297. It is outside this change and remains untouched while #488 integration is pending.
- Career Tweaker's whole-family Ensrick and Tourney controls already shipped under #445. They are bounded bulk presets with exact family catalogs and mutual exclusion.
- Chaos Wastes Tweaker's five requested families had stable owner boundaries but no umbrella controls. Those are implemented here as entry-point gates.

## CT owner contracts

| Master | Default | Children | Effective behavior |
| --- | ---: | ---: | --- |
| Enable altar reuse | on | 8 | Off restores vanilla one-use/one-cost behavior; saved numeric choices are retained. |
| Disable all listed curses | off | 14 | On treats every listed curse as disabled without rewriting individual choices. |
| Ban all grudge marks | off | 13 | On excludes every listed mark without rewriting individual choices. |
| Ban all weapon traits | off | 34 | On strips every listed trait from each detached generated/upgraded item, including unique archetypes, without rewriting individual choices. |
| Enable boon reworks | on | 5 | Off removes CT's five reworked trait-boon entries; saved child choices are retained. |

All five controls gate their existing feature-owner entry points. Trait bans also
pass through one final generated-item filter because vanilla unique archetypes
bypass baked trait pools and the legacy empty-pool safety fallback intentionally
keeps a weapon rollable. Vanilla accepts an empty trait list, so ban-all produces
a traitless item without exposing an empty random-choice operation. The controls
do not loop over `mod:set`, generate nested callbacks, add RPCs, or mutate network
lookups.

The three default-off bulk bans are first-row siblings inside their existing
collapsible groups, not checkbox parents. VMF hides a checkbox's `sub_widgets`
while it is unchecked; nesting here would make individual bans inaccessible
unless ban-all was already enabled. The default-on altar and boon controls retain
dependent children because hiding inactive tuning while those owners are off is
intentional.

## Bounded diagnostics

The mod emits one `[ct:221]` summary during initialization. `/ct_umbrella_audit` emits the same observation-only census on demand. It reports `altar_master`, `curses_master`, `grudges_master`, `traits_master`, and `boons_master` explicitly, followed by each active/total child count and `mutation=false`.

Expected totals are `altar=8`, `curses=14`, `grudges=13`, `traits=34`, and `boons=5`. A count change means the menu catalog and owner gate need to be reviewed together.

## Remaining Career Tweaker boundary

The historical plan also proposed masters for individual Career Tweaker implementation clusters (Unchained, Outcast Engineer, armor, and per-career groups). Those clusters span heterogeneous hook, template-mutation, and runtime owners; a menu-only checkbox would falsely imply complete gating. #445 already covers the safe whole-family use case. Per-cluster controls remain deliberately unimplemented until each cluster has an exact catalog, one reversible lifecycle owner, and tests proving that disabling the master restores vanilla behavior without erasing leaf selections.
