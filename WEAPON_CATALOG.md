# Weapon Catalog — Cross-Career Animation Reference

Per-weapon reference for attack chains, animation events, and cross-career status. Use this to plan and track animation work.

**Legend:**
- **Native** = works without any mod intervention on that character
- **OK** = tested working in-game (version noted)
- **Redirect** = stance redirect in `_career_anim_redirect` (wield event swapped)
- **Remap** = 3P attack remap table built (`_3p_template_remaps` / `_3p_key_remaps`)
- **Force-fire** = hardcoded `_original_animation_event` call (SM-corrupting events)
- **Untested** = unlockable but not verified in-game
- **Unknown** = data not yet collected

---

## 1H Hammers / Maces

**Template:** `one_handed_hammer_template_1` / `one_handed_hammer_template_2`
**Wield event:** `to_1h_hammer`
**Lights:** 4 — L1 `attack_swing_left_diagonal`, L2 `attack_swing_left_diagonal_last`, L3 `attack_swing_right_diagonal`, L4 `attack_swing_down_right`
**Heavies:** 2 — H1 `attack_swing_heavy_down`, H2 `attack_swing_heavy_down_right`
**Push-attack:** Yes — `attack_swing_right`
**Charge events:** `attack_swing_charge_left_diagonal`, `attack_swing_charge_left_diagonal_pose`, `attack_swing_charge_right_diagonal_pose`

### Weapon Keys

| Key | Native | Kruber | Bardin | Kerillian | Saltzpyre | Sienna |
|-----|--------|--------|--------|-----------|-----------|--------|
| `dr_1h_hammer` | Bardin | Untested | Native | **OK — Redirect** v0.10.10 | Untested | Untested |
| `es_1h_mace` | Kruber | Native | Untested | **OK — Redirect** v0.10.10 | Untested | Untested |
| `wh_1h_hammer` | Saltzpyre | Untested | Untested | **OK — Redirect** v0.10.10 | Native | Untested |

### Cross-Career Notes
- Kerillian: `to_1h_hammer` is phantom on her skeleton (TRUE in probe, no visible animation). Redirect to `to_1h_sword` fixes it. No attack remap needed — all hammer attack events work under sword stance.
- Scale override: `dr_1h_hammer` on `we_` = `{0.85, 0.85, 1}` (15% thinner X/Y)
- Grip offset: `wh_1h_hammer` on `es_` = `{0, 0, 0.15}`

---

## 1H Swords

**Template:** `one_handed_swords_template_1` (es/bw), `we_one_hand_sword_template_1` (elf)
**Wield event:** `to_1h_sword`
**Lights (es/bw):** 3 — L1 `attack_swing_left_diagonal`, L2 `attack_swing_right`, L3 `attack_swing_down`
**Lights (elf):** 3 — L1 `attack_swing_left_diagonal`, L2 `attack_swing_right`, L3 `attack_swing_down`
**Heavies (es/bw):** 2 — H1 `attack_swing_heavy`, H2 `attack_swing_heavy_right`
**Heavies (elf):** 3 — H1 `attack_swing_heavy_down`, H2 `attack_swing_heavy_left_up`, H3 `attack_swing_heavy_down_right`
**Push-attack:** Yes — es/bw: `attack_swing_right_diagonal`, elf: `attack_swing_stab`
**Charge events (es/bw):** `attack_swing_charge_left`, `attack_swing_charge_right_pose`, `attack_swing_charge_left_pose`

### Weapon Keys

| Key | Native | Kruber | Bardin | Kerillian | Saltzpyre | Sienna |
|-----|--------|--------|--------|-----------|-----------|--------|
| `we_1h_sword` | Kerillian | Untested | **OK — Remap** | Native | Untested | Untested |
| `es_1h_sword` | Kruber | Native | **OK — Remap** | Untested | Untested | Untested |
| `bw_sword` | Sienna | Untested | **OK — Remap** | Untested | Untested | Native |

### Cross-Career Notes
- `we_1h_sword` on non-Kerillian: key remap `attack_swing_stab → attack_swing_down` (L3), heavy remaps for H2/H3
- `es_1h_sword` / `bw_sword` on Bardin: key remap for 3-position heavy chain
- Scale: `we_1h_sword` on `es_`/`wh_` = 1.15, `dr_` = 1.10. `bw_sword` same pattern.
- Grip: `we_1h_sword`/`bw_sword`/`es_1h_sword` on `dr_` = `{0, 0, 0.05}`

---

## 1H Axes

**Template:** `one_handed_axes_template_1`
**Wield event:** `to_1h_axe`
**Lights:** 3 — L1 `attack_swing_left_diagonal`, L2 `attack_swing_right_diagonal`, L3 (last) pattern repeats
**Heavies:** 2 — H1 `attack_swing_heavy_down`, H2 `attack_swing_heavy_down_right`
**Push-attack:** Yes — `attack_swing_down_right`
**Charge events:** `attack_swing_charge_left_diagonal`

### Weapon Keys

| Key | Native | Kruber | Bardin | Kerillian | Saltzpyre | Sienna |
|-----|--------|--------|--------|-----------|-----------|--------|
| `dr_1h_axe` | Bardin | Untested | Native | Untested | Untested | Untested |
| `wh_1h_axe` | Saltzpyre | Untested | Untested | Untested | Native | Untested |

### Cross-Career Notes
- Redirect: Sienna (`bw_`) gets `to_1h_axe → to_1h_sword`. Priest gets `to_1h_hammer`.
- Scale: `dr_1h_axe` on `we_` = `{0.85, 0.85, 1}`

---

## Falchion

**Template:** `one_hand_falchion_template_1`
**Wield event:** `to_1h_falchion` (missing on all skeletons — redirect required)
**Lights:** 3 — L1 `attack_swing_left_diagonal`, L2 `attack_swing_right_diagonal`, L3 `attack_swing_down`
**Heavies:** 2 — H1 `attack_swing_heavy_left_diagonal`, H2 `attack_swing_heavy_right_diagonal`
**Push-attack:** Unknown
**Charge events:** `attack_swing_charge_left_diagonal`

### Weapon Keys

| Key | Native | Kruber | Bardin | Kerillian | Saltzpyre | Sienna |
|-----|--------|--------|--------|-----------|-----------|--------|
| `wh_1h_falchion` | Saltzpyre | Untested | Untested | Untested | Native | Untested |

### Cross-Career Notes
- `to_1h_falchion` doesn't exist on any skeleton. Priest redirect → `to_1h_hammer`. Other careers: Unknown — needs redirect.
- Template remap exists: `dr_` (Bardin) has 4 entries distinguishing heavy variants. `_default` has 5 entries.

---

## Crowbill

**Template:** `one_handed_crowbill`
**Wield event:** `to_1h_crowbill` (redirect needed for non-Sienna)
**Lights:** Unknown — need to collect
**Heavies:** Unknown — need to collect
**Push-attack:** Unknown
**Charge events:** Unknown

### Weapon Keys

| Key | Native | Kruber | Bardin | Kerillian | Saltzpyre | Sienna |
|-----|--------|--------|--------|-----------|-----------|--------|
| `bw_1h_crowbill` | Sienna | Untested | **OK — Remap** v0.9.93+ | Untested | Untested | Native |

### Cross-Career Notes
- Redirect: `to_1h_crowbill → to_1h_sword` (Sienna `bw_`). Priest → `to_1h_hammer`.
- Template remap: `dr_` override for H1/H3 overhead fixes (v0.9.119). `_default` has 4 entries. `attack_swing_left` NOT remapped (fires correctly natively on Kruber — v0.9.93).
- Scale: `bw_1h_crowbill` on `es_`/`wh_` = 1.10, `dr_` = 1.05

---

## 1H Flails

**Template:** `one_handed_flails_template_1` (es), `one_handed_flails_flaming_template` (bw)
**Wield event:** `to_1h_flail`
**Lights:** 4 — L1 `attack_swing_left_diagonal`, L2 `attack_swing_right_diagonal`, L3 `attack_swing_down`, L4 `attack_swing_down_right`
**Heavies:** 2 — H1 release `attack_swing_left` (charge: `attack_swing_charge`), H2 release `attack_swing_heavy_left` (charge: `attack_swing_charge_left`)
**Push-attack:** Yes — `attack_swing_right`
**Charge events:** `attack_swing_charge`, `attack_swing_charge_left`
**Note:** H1 release event is `attack_swing_left`, NOT a `heavy_` prefixed event — this is why it corrupts the SM when added to remap tables.

### Weapon Keys

| Key | Native | Kruber | Bardin | Kerillian | Saltzpyre | Sienna |
|-----|--------|--------|--------|-----------|-----------|--------|
| `es_1h_flail` | Saltzpyre | Untested | Untested | Untested | Native | Untested |
| `bw_1h_flail_flaming` | Sienna | Untested | Untested | Untested | Untested | Native |

### Cross-Career Notes
- `es_1h_flail` on non-Saltzpyre: H1 `attack_swing_left → attack_swing_heavy` and H2 `attack_swing_heavy_left → attack_swing_heavy` via **force-fire** (not remap table — SM corruption).
- `bw_1h_flail_flaming` on non-Sienna: only H2 `attack_swing_heavy_left → attack_swing_heavy` needs redirect (v0.9.92). H1 fires natively — DO NOT remap.
- Vanilla bug: `es_1h_flail` push-attack on Saltzpyre native — `attack_swing_right` produces no animation. Fixed via narrow redirect `attack_swing_right → attack_swing_right_diagonal` on `wh_` + `es_1h_flail` only (v0.9.96).

---

## Greatswords (2H Swords)

**Template:** `two_handed_swords_template_1` (es/wh), `two_handed_swords_wood_elf_template` (elf)

### Human Greatsword (es/wh)
**Wield event:** `to_2h_sword`
**Lights:** 2 — L1 `attack_swing_left_diagonal`, L2 `attack_swing_right_diagonal`
**Heavies:** 2 — H1 `attack_swing_heavy_left_diagonal`, H2 `attack_swing_heavy_right_diagonal`
**Push:** `attack_push`
**Push follow-up:** Yes — `attack_swing_down_right` (sub_action `light_attack_bopp`)
**Charge events:** `attack_swing_charge_diagonal`, `attack_swing_charge_diagonal_right`, `attack_swing_charge_diagonal_left`

### Elf Greatsword (we)
**Wield event:** `to_2h_sword_we`
**Lights:** 2 — L1 `attack_swing_right`, L2 `attack_swing_left`
**Heavies:** 2 — H1 `attack_swing_heavy`, H2 `attack_swing_heavy_right`
**Push-attack:** Yes — has push-attack sub_action
**Charge events:** `attack_swing_charge` (shared across all heavies)

### Weapon Keys

| Key | Native | Kruber | Bardin | Kerillian | Saltzpyre | Sienna |
|-----|--------|--------|--------|-----------|-----------|--------|
| `es_2h_sword` | Kruber | Native | Untested | **OK — Redirect + Remap** v0.10.16+ | Untested | Untested |
| `wh_2h_sword` | Saltzpyre | Untested | Untested | **OK — Redirect + Remap** v0.10.16+ | Native | Untested |
| `we_2h_sword` | Kerillian | Untested | Untested | Native | Untested | Untested |

### Cross-Career Notes
- Kerillian wielding es/wh greatsword: stance redirect `to_2h_sword → to_2h_sword_we`, plus template remap for 8 events (7 diagonal→cardinal + push-attack `attack_swing_down_right → attack_swing_heavy`). H1 release `attack_swing_heavy_left_diagonal → attack_swing_left` to match L1 visual.
- `to_2h_sword` FALSE on Kerillian, WPriest, Bardin skeletons. `to_2h_sword_we` only on Saltzpyre and Kerillian.
- Grip offset: `es_2h_sword`/`wh_2h_sword` on `we_` = `{0, 0, -0.085}`
- Scale: `we_2h_sword` on `es_` = 1.15
- Elf greatsword on Kruber/Saltzpyre: template remap exists (`_default` and `wh_` entries in `two_handed_swords_wood_elf_template`). Untested.

---

## Greataxe

**Template:** `two_handed_axes_template_1`
**Wield event:** `to_2h_axe` (missing on all skeletons — redirect required)
**Lights:** Unknown — need to collect
**Heavies:** Unknown — need to collect
**Push-attack:** Unknown

### Weapon Keys

| Key | Native | Kruber | Bardin | Kerillian | Saltzpyre | Sienna |
|-----|--------|--------|--------|-----------|-----------|--------|
| `dr_2h_axe` | Bardin | Untested | Native | Untested | Untested | Untested |

### Cross-Career Notes
- `to_2h_axe` doesn't exist on any skeleton — needs redirect. Unknown what redirect is in place.
- Template remap exists: `_default` has `attack_swing_up → attack_swing_left`, diagonal remaps.
- Scale: `dr_2h_axe` on `es_`/`wh_`/`we_`/`bw_` = `{1, 1.15, 1}` (Y-axis only)

---

## Greathammers (2H Hammer)

**Template:** Unknown — need to verify
**Wield event:** `to_2h_hammer`
**Lights:** Unknown — need to collect
**Heavies:** Unknown — need to collect
**Push-attack:** Unknown

### Weapon Keys

| Key | Native | Kruber | Bardin | Kerillian | Saltzpyre | Sienna |
|-----|--------|--------|--------|-----------|-----------|--------|
| `dr_2h_hammer` | Bardin | Untested | Native | Untested | Untested | Untested |
| `es_2h_hammer` | Kruber | Native | Untested | Untested | Untested | Untested |
| `wh_2h_hammer` | Saltzpyre (Priest) | Untested | Untested | Untested | Untested | Untested |

### Cross-Career Notes
- `to_2h_hammer` TRUE on all skeletons except Kerillian — may need redirect for her.

---

## Dual Hammers

**Template:** Unknown — need to verify
**Wield event:** `to_dual_hammers` (Bardin), `to_dual_hammers_priest` (Saltzpyre)
**Lights:** Unknown — need to collect
**Heavies:** Unknown — need to collect
**Push-attack:** Unknown

### Weapon Keys

| Key | Native | Kruber | Bardin | Kerillian | Saltzpyre | Sienna |
|-----|--------|--------|--------|-----------|-----------|--------|
| `dr_dual_wield_hammers` | Bardin | Untested | Native | Untested | Untested | Untested |
| `wh_dual_hammer` | Saltzpyre (Priest) | Untested | **OK — Redirect** v0.9.116 | Untested | Untested | Untested |

### Cross-Career Notes
- Saltzpyre's dual hammers fire `to_dual_hammers_priest` on wield — missing on Bardin's skeleton. Redirect to `to_dual_hammers` (v0.9.116).
- Grip: `wh_dual_hammer` on `dr_` = `{0, 0, 0.15}`
- `to_dual_wield` missing on all skeletons.

---

## Halberd

**Template:** `halberds_template_1`
**Wield event:** Unknown — need to verify
**Lights:** 4 — L1 `attack_swing_down_left`, L2 `attack_swing_down_right`, L3 `attack_swing_right`, L4 unknown
**Heavies:** 2 — H1 `attack_swing_heavy_right`, H2 `attack_swing_heavy`
**Push-attack:** Yes — `attack_swing_down_right` (from push chain)

### Weapon Keys

| Key | Native | Kruber | Bardin | Kerillian | Saltzpyre | Sienna |
|-----|--------|--------|--------|-----------|-----------|--------|
| `es_halberd` | Kruber | Native | Untested | Untested | Untested | Untested |

### Cross-Career Notes
- No redirect or remap in place. Untested on all non-Kruber careers.

---

## Polearms / Spears

**Template:** `spears_we_template_1` (elf spear), various deus templates (spear+shield)
**Wield events:** `to_spear` (elf), `to_polearm` (Kruber), `to_2h_billhook` (Saltzpyre)

### Weapon Keys

| Key | Native | Kruber | Bardin | Kerillian | Saltzpyre | Sienna |
|-----|--------|--------|--------|-----------|-----------|--------|
| `we_spear` | Kerillian | Redirect only | Untested | Native | **OK — Redirect + Remap** | Untested |
| `es_2h_heavy_spear` | Kruber | Native | Untested | Redirect only | Redirect only | Untested |

### Cross-Career Notes
- Elf spear on Saltzpyre: redirect `to_spear → to_2h_billhook`, remap `_3p_remap_spear_to_billhook` (12 entries + 3 force-fires). Fully working v0.7.1.
- Elf spear on Kruber: redirect `to_spear → to_polearm`, remap `_3p_remap_spear_to_polearm` (2 entries).
- Heavy spear on Saltzpyre: redirect `to_polearm → to_2h_billhook`, shares spear remap. Untested — may need own table.

---

## Spear + Shield

**Template:** `1h_spears_shield` (elf), `es_deus_01` (Kruber)
**Wield events:** `to_1h_spear_shield` (elf), `to_es_deus_01` (Kruber)

### Weapon Keys

| Key | Native | Kruber | Bardin | Kerillian | Saltzpyre | Sienna |
|-----|--------|--------|--------|-----------|-----------|--------|
| `we_1h_spears_shield` | Kerillian | Untested | Untested | Native | Untested | Untested |
| `es_deus_01` | Kruber | Native | Untested | **OK — Redirect + Remap** v0.10.21 | Untested | Untested |

### Cross-Career Notes
- Kruber spear+shield on Kerillian: redirect `to_es_deus_01 → to_1h_spear_shield`, remap `_3p_remap_deus_to_spear_shield` (1 entry: `attack_swing_up → attack_swing_stab_lh`). H2 `attack_swing_heavy_down_right` works natively on elf SM (v0.10.21 removed erroneous remap).
- Elf spear+shield on Kruber: redirect `to_1h_spear_shield → to_es_deus_01`, remap `_3p_remap_spear_shield_to_deus` (1 entry: `attack_swing_stab_lh → attack_swing_stab`).
- Bidirectional suffix remaps for `_1h_spear_shield` ↔ `_es_deus_01`.

---

## Billhook

**Template:** `2h_billhooks_template_1`
**Wield event:** `to_2h_billhook`
**Lights:** 3 — L1 `attack_swing_stab`, L2 `attack_swing_left_diagonal`, L3 loops
**Heavies:** 2 — H1 `attack_swing_heavy_stab`, H2 `attack_swing_heavy_left_diagonal`
**Push-attack:** `light_attack_bopp` — Unknown anim event
**Special:** Billhook event names are visually inverted (`heavy_stab` looks like diagonal, `heavy_left_diagonal` looks like stab)

### Weapon Keys

| Key | Native | Kruber | Bardin | Kerillian | Saltzpyre | Sienna |
|-----|--------|--------|--------|-----------|-----------|--------|
| `wh_2h_billhook` | Saltzpyre | Redirect only | Untested | Redirect only | Native | Untested |

### Cross-Career Notes
- Non-Saltzpyre: redirect `to_2h_billhook → to_polearm`, remap `_3p_remap_billhook_to_polearm` (14 entries).
- `to_2h_billhook` only exists on Saltzpyre and Sienna skeletons.
- `attack_swing_stab_02` corrupts SM when added to remap table — force-fire only.

---

## Shield Weapons

### Hammer + Shield

**Wield event:** `to_1h_hammer_shield` / `to_1h_hammer_shield_priest`
**Lights:** Unknown — need to collect
**Heavies:** Unknown — need to collect
**Push-attack:** Unknown

| Key | Native | Kruber | Bardin | Kerillian | Saltzpyre | Sienna |
|-----|--------|--------|--------|-----------|-----------|--------|
| `dr_shield_hammer` | Bardin | Untested | Native | Untested | Untested | Untested |
| `wh_hammer_shield` | Saltzpyre | Untested | Untested | Untested | Native | Untested |
| `wh_hammer_book` | Saltzpyre (Priest) | Untested | Untested | Untested | Native | Untested |
| `es_mace_shield` | Kruber | Native | Untested | Untested | Untested | Untested |

### Cross-Career Notes
- Grip: `wh_hammer_shield` on `es_` = `{0, 0, 0.15, hand = "right"}`
- Priest redirect: `to_1h_hammer_shield_priest → to_1h_hammer_shield`

### Sword + Shield

**Wield event:** `to_1h_sword_shield`

| Key | Native | Kruber | Bardin | Kerillian | Saltzpyre | Sienna |
|-----|--------|--------|--------|-----------|-----------|--------|
| `es_sword_shield_breton` | Kruber (QK) | Untested | Untested | Untested | Untested | Untested |

### Flail + Shield

**Wield event:** Unknown
**Attack chain:** Unknown — need to collect

| Key | Native | Kruber | Bardin | Kerillian | Saltzpyre | Sienna |
|-----|--------|--------|--------|-----------|-----------|--------|
| `wh_flail_shield` | Saltzpyre | Untested | Untested | Untested | Native | Untested |

---

## Ghost Scythe

**Template:** Unknown — need to verify
**Wield event:** Unknown
**Lights:** Unknown — need to collect
**Heavies:** Unknown — need to collect
**Push-attack:** Unknown

| Key | Native | Kruber | Bardin | Kerillian | Saltzpyre | Sienna |
|-----|--------|--------|--------|-----------|-----------|--------|
| `bw_ghost_scythe` | Sienna | Untested | Untested | Untested | Untested | Native |

### Cross-Career Notes
- Ghost scythe IS intentionally allowed on non-necromancer Sienna careers. Do NOT remove it.
- Known crash: `wpn_bw_ghost_scythe_01_3p` unit not found when bot Sienna equips it. Needs investigation.

---

## Data Collection Needed

The following weapons/combinations have incomplete data. Use `wt animlog`, `wt force3p`, and `wt dump_actions` to fill in gaps.

### Missing Attack Chain Data
- Crowbill: light chain, heavy chain, push-attack events
- Greataxe (`dr_2h_axe`): full chain
- Greathammer (`dr_2h_hammer`, `es_2h_hammer`, `wh_2h_hammer`): full chain, template name
- Dual hammers (`dr_dual_wield_hammers`, `wh_dual_hammer`): full chain, template name
- Halberd (`es_halberd`): L4 event, wield event confirmation
- All shield weapons: full attack chains
- Flail+shield (`wh_flail_shield`): wield event, full chain
- Ghost scythe (`bw_ghost_scythe`): wield event, full chain, template name

### Untested Cross-Career Combinations (Priority)
High priority — weapons are unlocked but 3P animations never verified:
1. **Any weapon on Bardin** (except confirmed: `we_1h_sword`, `bw_sword`, `es_1h_sword`, `bw_1h_crowbill`, `wh_dual_hammer`)
2. **Any weapon on Sienna** (zero confirmed)
3. **Greathammers cross-career** (zero confirmed on any character)
4. **Halberd cross-career** (no redirect, no remap, completely untouched)
5. **Shield weapons cross-career** (zero confirmed except Kruber spear+shield on Kerillian)
6. **Elf greatsword on Kruber/Saltzpyre** (template remap exists but untested)

### Process Reminder
See `reference_3p_anim_fix_process.md` for the step-by-step workflow. Key points:
1. `wt animlog` → identify missing 3P events
2. `wt force3p <event>` → visually verify candidate targets
3. TRUE in skeleton probe ≠ visible animation — always verify visually
4. When animlog is insufficient, compile event list from template file and have user test with `wt force3p`
