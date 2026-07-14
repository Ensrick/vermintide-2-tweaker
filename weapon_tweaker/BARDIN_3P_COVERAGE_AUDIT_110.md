# Bardin cross-character 3P audit (#110)

The live `wt_unlock_data.lua` catalog gives each Bardin career the same five
cross-character ports. Source and the existing coverage ledger classify every
row as working:

| Weapon | Status | Display evidence |
|---|---|---|
| `we_1h_sword` | `[working]` | Bardin-scoped 1H event remap, scale, and grip |
| `es_1h_sword` | `[working]` | Bardin-scoped 1H event remap and grip |
| `wh_1h_falchion` | `[working]` | Bardin-scoped heavy-event differentiation |
| `bw_1h_crowbill` | `[working]` | Bardin-scoped missing-event remap and scale |
| `es_handgun` | `[working]` | native Bardin `to_handgun` template vocabulary |

The only runtime discrepancy was status bookkeeping: `es_handgun` is not
prefix-native, so the resolver defaulted it to `[needs animations]` even though
the Bardin body and coverage use the native handgun vocabulary. It is now an
explicit confirmed row.

The four melee rows have event-level remap tables, not a single borrowed weapon
SET. Their dev annotation therefore says `Bardin 1H event map`; naming a specific
weapon would overstate the source. Empire Handgun has no redirect annotation and
all five have no model substitute.

At load, WT writes one `[wt:110]` census to the log. `/wt_audit_bardin_3p`
emits the complete five-row record on demand. Offline coverage locks exact
career parity, five working rows, zero pending/untested/picker rows, honest
display metadata, and the bounded diagnostic wiring.
