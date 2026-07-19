# Zealot Flagellation rework (#447)

Version 0.3.72-dev adds the opt-in **Zealot: Replace Devotion with
Flagellation** rework. When Devotion is selected, temporary health produced by
the active level-5 THP talent also converts permanent health equal to half the
temporary health actually gained. A four-THP proc therefore converts two green
health; if only three green health remains, conversion is capped at three.

## Exact attribution

All three Zealot level-5 talents attach the ordinary `thp_linesman`,
`thp_smiter`, or `thp_tank` templates (`talent_settings_victor.lua:1402-1438`).
Those templates dispatch through four native proc functions
(`buff_templates.lua:434-750`). The module wraps only the functions referenced
by those three live templates and opens a weak-key, synchronous context around
the original call. The consolidated `PlayerUnitHealthExtension.add_heal` hook
converts health only inside that context.

This boundary excludes Natural Bond, consumables, career abilities, boons, and
unrelated `heal_from_proc` sources. Vanilla applies and caps THP first
(`player_unit_health_extension.lua:842-899`); the module measures the resulting
temporary-health delta, then uses vanilla `convert_to_temp`, whose server branch
caps the conversion to current permanent health (`:1187-1207`). No custom buff,
RPC, or `NetworkLookup` entry is introduced.

## Live talent resolution

The live game exposes exactly the decompile's 21 `victor_zealot_*` talents
(census 2026-07-18 vs `talent_settings_victor.lua`), but none is internally
named `victor_zealot_devotion`, so Devotion is still resolved from raw loc
data at runtime. Vanilla derives a talent title via
`Localize(display_name or name)` (`hero_window_talents.lua:328`); only the
three `thp_*` talents carry `display_name`
(`talent_settings_victor.lua:1408/1420/1432`), so the internal name is the
usual title key. The resolver localizes that `display_key` per candidate,
counts the engine's `<key>` unknown-key wrapper
(`localization_manager.lua:3-5`) as unresolved, and accepts only an
EXACTLY-ONE match on the Devotion identity. Boot always logs
`[crt:447] census candidates=N resolved=N unresolved=N matches=N`; a healthy
run shows `candidates=21 resolved=21 unresolved=0 matches=1` then
`resolved Devotion internal=...`. On failure the feature stays inert, emits
the bounded candidate census with real titles, and the consolidated Localize
hook retries resolution exactly once at the first menu localization. Once
resolved, that hook changes only the talent's title and description while the
toggle is on (override keys: the talent's `display_key` and `description`).

Flagellation and the existing Holy Fervour green-health conversion are two
alternative THP conversion models. They share the `zealot_thp_conversions`
mutex cluster, so enabling either toggle disables the other. Flagellation is
also registered in the native rework catalog and is included when the Ensrick
family master is enabled.

## Solo verification

1. Enable the rework and equip Devotion plus any Zealot level-5 THP talent.
2. Begin with green health and generate a known THP amount. Four realized THP
   should additionally convert two green health to THP.
3. Repeat near maximum combined health; conversion must use the realized,
   post-cap THP gain rather than the nominal proc value.
4. Trigger Natural Bond and use healing supplies. Neither should convert green
   health.
5. Select another level-25 talent. Level-5 THP gains must stop converting.
6. Run `/crt_regression_test`; `issue447_flagellation_contract` must pass.
