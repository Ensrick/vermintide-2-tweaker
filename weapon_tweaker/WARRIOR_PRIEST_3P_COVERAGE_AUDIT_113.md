# Warrior Priest cross-character 3P audit (#113)

Warrior Priest is a separate melee-only receiver, not a fourth member of the
ordinary Saltzpyre coverage bucket. Its live unlock catalog contains exactly
seven weapons:

| Kind | Count | Keys |
|---|---:|---|
| Native | 6 | `wh_1h_hammer`, `wh_2h_hammer`, `wh_dual_hammer`, `wh_flail_shield`, `wh_hammer_book`, `wh_hammer_shield` |
| Cross-character | 1 | `es_1h_flail` |

The Empire Flail is `[working]`. It keeps the flail wield vocabulary on the
Warrior Priest body and uses the shipped per-unit push/heavy event correction;
the dev label now describes this as the Warrior Priest flail event map. No model
substitute is shipped or queued, and the row is not picker-visible.

The catalog audit uses a fixed seven-key allow-list deliberately. A later
unexpected entry is therefore reported rather than treated as acceptable merely
because it shares Saltzpyre's `wh_` prefix. This protects the melee-only boundary
against both ranged additions and ordinary-Saltzpyre availability drift.

WT writes one bounded `[wt:113]` startup census. The optional
`/wt_audit_warrior_priest_3p` command logs the single cross-character row with
status, target, model, and picker state. Neither path mutates unlocks, templates,
animation events, settings, or network state.
