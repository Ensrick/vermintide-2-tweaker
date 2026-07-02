# Career Tweaker — TODO

## Deferred / planned

- [ ] **Restore the old level-5 THP talents (icons, names, descriptions).** The level-5
  "temp health on X" talent row (the `*_thp_tank` / `*_thp_linesman` / `*_thp_smiter`
  trio every career shares — e.g. `bardin_engineer_thp_tank/linesman/smiter`) was
  reworked at some point; restore the **old** talent **icons**, **names**, and
  **descriptions** for them as a crt feature/toggle. Cosmetic-only (the underlying
  THP mechanic stays); a data swap on `Talents[hero][talent_id].icon` /
  `.display_name` / `.description` with snapshot/restore, per the existing
  `rework_*` framework in `career_tweaker_balance.lua`. Cross-career (all 15 careers
  carry the level-5 THP row). Will need the old icon atlas-keys + old loc strings
  (likely pulled from an older VT2 decompile, same approach as the Leading Shots
  research). Requested 2026-06-18 — "we'll do it another time."

- [ ] **Leading Shots restoration** (Outcast Engineer, replaces Ingenious Ordnance) —
  in progress 2026-06-18. Research complete (mechanic: every 4th ranged shot a
  guaranteed crit; icon `bardin_engineer_ranged_crit_count` orphaned in
  gui_icons_atlas; target talent `bardin_engineer_improved_explosives` slot [2,1]).
  Implementation needs a **custom on_ammo_used counter buff_func** (no data primitive
  exists) + the guaranteed_crit perk chain. See the Leading Shots research workflow
  output + plan.
