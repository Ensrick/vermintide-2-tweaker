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

The installed game is newer than the repository's decompile in this talent
area. The module therefore resolves Devotion from the live Zealot talent table
by its localized title rather than guessing an internal identifier. If it is
not found, the feature stays inert and automatically emits a bounded
`[crt:447]` candidate census. Once resolved, the existing consolidated Localize
hook changes only that talent's title and description while the toggle is on.

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
