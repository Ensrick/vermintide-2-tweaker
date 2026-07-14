# Kruber cross-character 3P audit (#109)

`wt_unlock_data.lua` is the inventory source of truth. At v0.12.244-dev each
Kruber career exposes the same 52 distinct non-`es_` ports:

| State | Count | Meaning |
|---|---:|---|
| `[working]` | 37 | Baked/confirmed or deliberately native fall-through |
| `[needs animations]` | 13 | Wield SET may be wired, but per-attack 3P behavior is not confirmed |
| `[untested]` | 2 | Javelin and Deepwood Staff still need a receiver decision |
| `[needs offsets]` | 0 | No Kruber offset-only row remains |

The old issue snapshot counted 51. Since then native Bardin Dual Axes was removed,
while the independently WT-owned Axe & Falchion and Saltzpyre Crossbow became
live rows, producing the current 52. It also described several subsequently
baked ports as pending. Moonfire Bow was the documented
coverage gap; source proves its Kruber wield SET is Empire Longbow
(`we_deus_01_template_1 -> to_es_longbow`), but no Kruber-scoped per-attack bake
exists, so it remains `[needs animations]` rather than being promoted to working.

## Diagnostics contract

The mod now performs a bounded, read-only audit once at load and writes one
`[wt:109]` summary to the console log. `/wt_audit_kruber_3p` writes every
non-working row with its source-backed target and picker visibility. It does not
mutate templates, settings, unlocks, or NetworkLookup tables.

The 13 `[needs animations]` rows are intentionally reported as hidden from the
static picker: its hardcoded template/attack vocabularies do not yet cover them.
Adding only allow-list membership would create empty or misleading controls.
The two `[untested]` rows remain outside the picker by design.

## Potential-fix queue

1. Add static picker vocabularies in small, source-compatible batches, beginning
   with Moonfire/shortbows and the three receiver-native firearm targets.
2. Capture and bake Kruber-scoped per-attack maps; keep native-owner scopes false.
3. Decide targets for `we_javelin`, `we_life_staff`, `wh_crossbow`, and
   `wh_dual_wield_axe_falchion` before claiming them working.
4. Verify locally in third person and in inventory preview. A remote-husk check
   is required only where model substitution or transform state is introduced.

Offline regression coverage locks the 52-row career parity, the 37/13/2 status
split, Moonfire's source-backed target, unknown-target honesty, and both automatic
and on-demand diagnostic wiring.
