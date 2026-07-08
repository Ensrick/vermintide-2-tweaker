# Dev Mod Testing Status

Tracks which **dev-mod** features are verified working in-game, so we know what's
safe to promote to the stable/public mods. The in-menu `[untested]` /
`[working]` labels are the live source of truth; this doc adds the
non-menu features, known issues, and the process.

## The labeling system

Every menu entry in the five `*_dev` mods carries a status label, prefixed onto
its VMF menu display name:

- **`[untested]`** — added or changed in dev, not yet verified in-game. The
  default for every new dev feature.
- **`[working]`** — verified in-game by the user. A promotion candidate
  for the matching stable mod.

Stable / public mods (`ct`, `gt`, `cim`, `verminious_dreams_lighting`, and every
single-stream mod) carry **no** labels — anything shipped there is assumed to
work unless a current issue says otherwise.

### Coverage (bulk-labeled 2026-06-19)

| Dev mod | Menu widgets labeled | Confirmed working |
|---|---|---|
| `chaos_wastes_tweaker_dev` (ct_dev) | 123 static + the dynamic CW-scenario / adventure-mission map toggles | The Skittergate |
| `general_tweaker_dev` (gt_dev) | 135 | Necromancer potion handoff; Ironbreaker revive-in-ult |
| `crafting_in_modded_dev` (cim_dev) | 8 | — |
| `verminious_dreams_lighting_dev` (vdl_dev) | 3 | — |

Not labeled: group headers, tooltips, dropdown options, and the
`enable_debug_logging` utility toggle (a logging utility, not a gameplay
feature). The CW map labels are applied in the dynamic loop at the bottom of
`chaos_wastes_tweaker_dev_localization.lua` (the per-map labels are generated
from `_adventure_pool.lua`, so they aren't static loc entries).

`gui_tweaker_dev` (gut_dev), the fifth split-mod dev clone, is not in the
2026-06-19 snapshot above; it currently carries 58 `[working]` + 14 `[untested]`
menu labels.

### weapon_tweaker (single-stream) — ANIMATION test-status (2026-06-19)

wt is single-stream (no stable counterpart), but its release gate is 3P
animations, so the weapon availability menu is labeled by **animation** status:
- **Cross-character entries** (receiver char ≠ weapon owner — the 3P-remap
  testing surface): **633 `[untested]`**, **15 `[working]`**.
- **Same-character entries** (native skeleton — animations work by default):
  left unlabeled (299 entries).
- Labeler: `tools/label-untested/` companion `%TEMP%\label_wt_anim.ps1` (keyed on
  the `unlock_<receiverchar>_<career>_<owner>_<type>` setting-id scheme; confirmed
  weapons matched by `<owner>_<type>` weapon key).

## Process (going forward)

- Every **new dev menu entry** ships `[untested]`.
- Every **new dev feature without a menu entry** gets a row in *Non-menu
  features* below, marked `[untested]`.
- When the user confirms a feature works in-game, flip its label to
  `[working]` (menu) or update its row here (non-menu).
- `[working]` features are the promotion candidates for the stable
  mods.

## Confirmed working

- **gt_dev** — Necromancer bots can hand off potions (`gt_bot_necro_potion_handoff`).
- **gt_dev** — Ironbreaker bots revive during their ult (`gt_bot_ironbreaker_revive_in_ult`).
- **ct_dev** — CW adventure-map injection: **The Skittergate**.
- **weapon_tweaker** (animations) — **Kerillian: Spear** (`we_spear`) and **Saltzpyre: Axe** (`wh_1h_axe`), cross-character, all receivers.
- **weapon_tweaker** (animations) — **Saltzpyre: Billhook** (`wh_2h_billhook`) on all **Kruber** careers only (Mercenary / Huntsman / Foot Knight / Grail Knight); other receivers stay `[untested]`.

## crt (single-stream) — new Armor & Overcharge toggles (2026-06-20, v0.3.32-dev)

All four `[untested]` (menu labels are the live source of truth). Host-authoritative
except where noted. Verify in a real session, then flip the menu prefix to
`[working]`.

- **crt** — `armor_gromril_ignore_chip` — Gromril (Ironbreaker) + Cursed Armor
  (Necromancer, per-peer) not consumed by chip/DoT/AOE. `[untested]`
- **crt** — `armor_specials_dont_break_gromril` — specials don't break Gromril
  unless Gromril Curse talent. `[untested]`
- **crt** — `unchained_no_overcharge_from_ff` — no overcharge from friendly fire. `[untested]`
- **crt** — `unchained_no_overcharge_from_disablers` — no overcharge from special
  disablers. `[untested]`

## Known issues (NOT confirmed; left `[untested]`)

- **ct_dev — Tower of Treachery** (CW adventure-map injection, `dlc_wizards_tower`):
  the **gargoyle skull does not appear in the chest** ("somehow it's gone") — a
  level-objective pickup is not spawning on the injected map. Needs a console log
  to diagnose when we're ready to fix; left `[untested]` until verified.

## Non-menu features (tracked manually)

_None yet — every current dev feature has a menu toggle and is tracked by its
in-menu label. New code-only features (always-on fixes, internal behaviors) go
here as `[untested]` and flip to `[working]` on verification._
