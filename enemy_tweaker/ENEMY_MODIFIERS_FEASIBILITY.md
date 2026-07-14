# Issue 453: enemy modifiers

## Resolved catalog

The request maps to 15 native modifier templates:

- the 13 standard entries in `BossGrudgeMarks`;
- Repulse, which Geheimnisnacht authors as the `shockwave` enhancement and
  `grudge_mark_shockwave_attacks` buff;
- Devious Delvings Berserk, which is the distinct `termite_base` enhancement's
  `grudge_mark_termite_boss_raging` buff (not ordinary Raging or Frenzy).

The four requested target categories are disjoint: Lords are Enemy Tweaker's
curated chapter-boss set; Bosses are other `breed.boss` units; Specials use
`breed.special`; Elites use `breed.elite`.

## Diagnostics

Enemy Tweaker v0.7.49-dev logs one `[et:453]` readiness line at startup. Run
`/et_modifier_audit` for the bounded detail census: one summary and 15 modifier
rows are written to the current log, while chat receives one summary only.

The audit proves each root buff template exists, has a symmetric vanilla
`NetworkLookup.buff_templates` pair, remains inside its authored
`BreedEnhancements` row, and that all four target categories contain breeds. It
now follows each `buff_to_add*` child chain (hard cap 32 templates), checks every
child template and wire id, and resolves named apply/update/event/remove callback
fields through `BuffFunctionTemplates.functions`. A top-level id can no longer
hide a broken child or callback contract.

The singleton post-spawn hook also performs an automatic, read-only live census
for at most two distinct breeds in each category (eight rows per session). Each
`[et:453] live` row reports buff/health extensions, blackboard/navigation,
position, side, race, network game-object id, pre-existing enhancements, native
breed bans, and how many of the 15 modifiers meet their source-derived runtime
prerequisites. It never calls `add_buff`, `set_attribute`, or starts an event.

Run `/et_regression_test` and require `issue453_modifier_catalog_wire_ready` and
`issue453_live_prerequisite_probe_bounded` to pass. Let representative Specials,
Elites, Bosses, and Lords spawn normally and attach the eight live rows. This
diagnostic is solo; a behavior implementation must be tested co-op.

## Safe implementation boundary

`_et_boss_grudge.lua` already owns the single
`ConflictDirector._post_spawn_unit` hook. VMF silently drops a second hook on
the same pair, so the feature must be consolidated there rather than adding a
new spawn hook.

The host should classify the spawned breed, roll that category's configured
rate once, choose only among enabled modifiers, honor vanilla exclusion/banned
tables, and add vanilla templates as server-controlled buffs. Do not mutate
shared breeds or `BreedEnhancements`; do not send modifier names in a new RPC.
Vanilla `rpc_add_buff` already carries stable template IDs to clients.

Before exposing the full 15-by-4 surface, require zero transitive/function gaps
and live prerequisite evidence for representative breeds. Then verify one ordinary grudge mark plus
each event-only modifier on a non-monster target. Several templates were
authored for monsters/events and may contain target-shape assumptions even when
their registration and wire identity are valid.

## Source evidence

- `scripts/settings/grudge_mark_settings.lua:31-119`: enhancement-to-buff map.
- `scripts/settings/grudge_mark_settings.lua:126-141`: 13 standard boss marks.
- `scripts/settings/dlcs/geheimnisnacht_2021/geheimnisnacht_2021_generic_terror_events.lua:8-20`:
  Geheimnisnacht selects `shockwave` or `ignore_death_aura` for its elite.
- `scripts/settings/grudge_mark_settings.lua:16-20`: Devious Delvings
  `termite_base` includes its distinct raging buff.
- `scripts/settings/terror_events/terror_event_utils.lua:80-104`: native
  enhancement application path.
- `scripts/settings/dlcs/grudge_marks/buff_settings_grudge_marks.lua:83-649`:
  root and child buff templates; `:674-1490` owns their named callback bodies.
