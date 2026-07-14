# Saltzpyre non-Warrior-Priest cross-character 3P audit (#112)

The live unlock source gives `wh_captain`, `wh_bountyhunter`, and `wh_zealot`
the same 54 distinct non-`wh_` ports. The old issue snapshot counted 61 before
later ownership and redundancy removals. At v0.12.247-dev the live split is:

| State | Count | Meaning |
|---|---:|---|
| `[working]` | 37 | confirmed/baked or source-proven receiver behavior |
| `[needs animations]` | 17 | visual verification or per-attack work remains |
| `[untested]` | 0 | every live port has at least a recorded decision |
| `[needs offsets]` | 0 | no offset-only row remains |

The source-character composition is 17 Kruber, 10 Bardin, 15 Kerillian, and 12
Sienna ports. Empire Mace, Empire Sword, and Kerillian 1H Axe are now explicitly
working rather than falling through to the generic pending label. Bardin Dual
Hammers is absent from every live non-WP unlock list and has no Saltzpyre picker
catalog, so its stale status declaration was removed rather than preserved as an
unreachable tuning row.

Only two pending ports are picker-visible: Ensorcelled Reaper and Elf Spear,
both reopened by #576 after visible animation failures. Thirteen additional
pending rows have a source- or coverage-backed receiver target displayed for
diagnostics, but no matching static picker catalog; they remain hidden to avoid
empty or misleading controls. Shortbow and Hagbane are the final two pending
rows without a shipped target: their Volley Crossbow model substitution is
queued design work, not current runtime behavior.

WT writes one bounded `[wt:112]` startup census that verifies all three careers'
parity. `/wt_audit_saltzpyre_3p` logs only the 17 unresolved rows with target,
picker, and shipped-model state. The audit is read-only and does not mutate
unlocks, templates, animation events, settings, or network state.
