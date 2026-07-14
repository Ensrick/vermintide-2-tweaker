# Kerillian cross-character 3P audit (#111)

The live unlock catalog gives all four Kerillian careers the same 60 distinct
non-`we_` ports. At v0.12.246-dev the source-derived split is:

| State | Count | Meaning |
|---|---:|---|
| `[working]` | 44 | confirmed/baked or proven receiver-native behavior |
| `[needs animations]` | 14 | ranged target decided; per-attack map not baked |
| `[untested]` | 2 | no receiver target documented |
| `[needs offsets]` | 0 | no offset-only Kerillian row remains |

The issue's 11-confirmed snapshot is stale: a 33-port Kerillian picker batch and
later confirmed rows were baked after it was written. Conversely, the remaining
14 ranged rows are not picker-ready merely because their SET target is known.
The static picker contains no corresponding template/attack catalogs, so force-
adding allow-list entries would create empty or misleading controls.

All 14 decided ranged rows target the Elf Repeater Crossbow vocabulary:

- Bardin: Crossbow, Trollhammer, Drakefire Pistols, Drakegun, Grudge-Raker,
  Masterwork Pistol;
- Kruber: Blunderbuss, Handgun, Repeater Handgun;
- Saltzpyre: Brace, Crossbow, Volley Crossbow, Griffon-foot, Repeater Pistol.

`es_1h_mace` and `es_longbow` have no receiver decision in the coverage source.
They are therefore explicitly `[untested]` and expose no target label. No model
substitute is currently shipped for Kerillian; queued substitutes remain queued.

WT writes one bounded `[wt:111]` startup census. `/wt_audit_kerillian_3p` logs
only the 16 unresolved rows, including target and picker state. The next safe
implementation is a small ranged static-picker batch with source-event catalogs,
followed by captured Kerillian-scoped picks and baking. The two untested rows need
a user/source decision before entering that pipeline.
