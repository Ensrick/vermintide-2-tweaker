# wt 3P Animation Coverage Matrix

> **CORRECTION 2026-07-03 (v0.12.203-dev):** the v0.12.201 claim below ("all 35 were
> baked") was WRONG. The picker stores picks under two config namespaces (weapon-only
> vs template-qualified); v0.12.201 read only weapon-only, capturing Kerillian but
> DROPPING ~30 Kruber/Saltzpyre event-picks (billhook polearm, dual axes, crowbill,
> flaming flail, staves) - they T-posed. v0.12.203 regenerates a FAITHFUL image of the
> tester config for all 3 receivers by merging both namespaces: `we_` 33 (byte-identical
> to v0.12.201), `es_` (Kruber) 21, `wh_` (Saltzpyre) 20. See memory
> `reference_wt_anim_picker_two_key_namespaces` + CHANGELOG v0.12.203.

> **UPDATE 2026-07-03 (v0.12.201-dev):** the tester fully tuned every open
> `[Needs Animations]` port across all three pickers; all **35** were baked
> career-scoped into `_3p_template_remaps` and moved to `_CONFIRMED`
> (`wt_port_status.lua`): **Kerillian batch-1 (33 ports)**, **Saltzpyre
> Executioner Sword** (`es_2h_sword_executioner`, #160), and **Kruber
> Skullsplitter & Tome** (`wh_hammer_book`, #181 - tuned as a full anim remap,
> not a mesh-swap). The Kerillian/Kruber picker gates are now empty; the stale
> baked picker tables were cleaned up in lockstep.
>
> **Then queued Saltzpyre batch-2 (11 ports)** into the dev 3P Anim Picker for the
> tester: **WP Greathammer (A)** `es_2h_hammer`, `dr_2h_cog_hammer`, `dr_2h_pick`,
> `bw_1h_mace`, `bw_ghost_scythe`; **WP Dual Hammers (B)** `dr_dual_wield_hammers`;
> **2H Sword (G)** `es_bastard_sword`; **Dual Axe & Falchion (C)** `es_mace_shield`,
> `es_sword_shield`, `es_sword_shield_breton`, `dr_shield_axe` (shield ports - the
> right-hand weapon is the tunable render; the shield offhand model is a later pass).
> Picker wiring only, nothing baked - `_NEEDS_ANIMS.saltzpyre` + `_SALTZ_*` picker
> tables (`wt_dev_anim_picker.lua`) carry these 11.

> **UPDATE 2026-07-13 (v0.12.213-dev, #519):** the tester finished Saltzpyre batch-2;
> **10 of the 11** ports were fully tuned (every dropdown set) and BAKED career-scoped
> (`wh_`) into `_3p_template_remaps` (`_wt_anim_remap.lua`) - 129 picks, both config
> namespaces parsed per `reference_wt_anim_picker_two_key_namespaces` (all lived in
> weapon-only; template-qualified residuals were already baked in v0.12.203). Moved to
> `_CONFIRMED.saltzpyre` + removed from the picker. **`dr_dual_wield_hammers` had ZERO
> non-unset picks** in either namespace - NOT baked, still queued in the picker.
> All 10 rows below are 🔧 wired-unverified until the user eyeballs them in-game.


> Generated 2026-06-11 from a full source audit (wt v0.12.118-dev) of
> `wt_unlock_data.lua` (`weapon_unlock_map`) cross-referenced against every
> remap layer, template patcher, and model-substitute hook in
> `weapon_tweaker.lua`, plus `CROSS_CHARACTER_PORT_DECISIONS.md` (DECISIONS).
> **This is the release walk list**: wt ships when every non-native row below
> is WORKING or deliberately cut. Update statuses here as ports get verified
> in-game — this file is the single source of truth for "what's left".

## How to work a row (the tuning loop)

1. **In-game**: Mod Options → wt → *3P Animation Picker* → receiver character →
   port group. Pick wield + per-attack events from the dropdowns (live-applies +
   auto-rewields). Eyeball in 3P via gt's `/tp`. `/animlog` traces what fires.
2. Since v0.12.118 picks **persist across restarts** (boot re-apply) — tune over
   as many sessions as needed.
3. **Export**: `/wt_dump_anim_picks <character>` → paste-ready
   `_<PORT>_WIELD_3P` / `_<PORT>_ANIM_REMAP_3P` blocks in the console log.
4. **Bake**: hand the dump to Claude → it lands in the patcher tables + this file
   flips to WORKING. Two destinations by pick kind:
   - **Wield stance** (`to_*` events) → `_WIELD_ANIM_CAREER_3P_PATCHES`
     (`wt_wield_patches.lua`), career-scoped (`es_*` only for a Kruber port).
   - **Per-attack picks** (`attack_*`/`parry_*`/`attack_push`) → a CAREER-SCOPED
     `es_`-keyed entry in `_3p_template_remaps` (`weapon_tweaker.lua`), with the
     native owner's prefix set to `false` so the owner's 3P is never touched.
     NEVER raw-write the shared template's `anim_event_3p` — that corrupts the
     native owner (see the BAKED section in `KRUBER_3P_ANIM_DECISIONS.md`,
     v0.12.149-dev). Then REMOVE the weapon_key from `_NEEDS_ANIMS.kruber` and add
     it to `_CONFIRMED.kruber` (`wt_port_status.lua`) so the picker drops it and
     the Availability tag reads `[working]` (v0.12.204-dev #301: lowercased).
   Model substitutes (column b) are a separate wiring pass — see
   "Model-substitute queue" at the bottom.

**Legend** — ✅ WORKING (wired + verified) · 🔧 WIRED? (plumbing exists,
needs in-game verify) · 📋 DECIDED (target chosen in DECISIONS, NOT wired —
Wave 2/3 backlog) · ❓ UNDECIDED · 🔁 native (receiver's own vocab, no work) ·
🧊 known issue.

---

## Receiver: KRUBER (es_mercenary / es_huntsman / es_knight / es_questingknight)

All `es_*` natives 🔁 (halberd/heavy-spear carry belt-and-suspenders patcher
entries; longbow has zoom toggles).

| weapon_key | Display name | Status | Strategy / notes |
|---|---|---|---|
| wh_brace_of_pistols | Brace of Pistols | ✅ | **Flagship model sub** → Repeater Handgun 3P (mission + preview + left-pistol hide). Illusion-matched skin swap designed but NOT wired (resolver used by diag commands only) |
| wh_repeating_pistols | Repeater Pistol | ✅ | Model sub → Repeater Handgun (patcher remap deliberately empty) |
| dr_2h_axe | Bardin: Greataxe | ✅ | Remap (`two_handed_axes_template_1._default`) + scale 1.15 |
| we_2h_sword | Elf Greatsword | ✅ | Redirect `to_2h_sword_we→to_bastard_sword` + template remap + scale |
| we_spear | Elf Spear | ✅ | Patcher es_→`to_polearm` + spear remap |
| we_1h_spears_shield | Elf Spear & Shield | ✅ | Suffix `_1h_spear_shield→_es_deus_01` route |
| we_1h_sword | Elf Sword | ✅ | Key remap + scale |
| we_longbow | Elf Longbow | ✅ | Redirect `to_longbow→to_es_longbow` ("looks better than elf anims") |
| wh_2h_billhook | Saltzpyre: Billhook | ✅ | Patcher + billhook→polearm remap (v0.12.102 fix) |
| wh_1h_axe | Saltzpyre: 1H Axe | ✅ | Native `to_1h_axe` vocab — confirmed (DECISIONS:148) |
| es_1h_flail | Empire Flail | 🔁 | native |
| bw_1h_crowbill | Sienna: Crowbill | 🧊 | Remap wired + scale, but **Kruber heavy-attack regression** — user to retest (DECISIONS:35) |
| bw_1h_flail_flaming | Sienna: Flaming Flail | ✅ | Wield redirect `to_1h_flail_flaming→to_1h_flail` (DECISIONS:36 fix); capture-confirmed v0.12.139-dev → excluded from chooser |
| dr_dual_wield_axes | Bardin: Dual Axes | ✅ | **[Working] — BAKED v0.12.149-dev** career-scoped `_3p_template_remaps.dual_wield_axes_template_1.es_` (Empire Mace & Sword); removed from picker |
| dr_2h_pick | Bardin: Pickaxe | ✅ | **[Working] — BAKED v0.12.149-dev** career-scoped `_3p_template_remaps.two_handed_picks_template_1.es_` (Empire Greathammer); removed from picker |
| dr_2h_cog_hammer | Cog Hammer | ✅ | **[Working] — BAKED v0.12.151-dev** career-scoped `_3p_template_remaps.two_handed_cog_hammers_template_1.es_` (Empire Greathammer); all-identity picks (already animates correctly on Kruber); `dr_ = false` keeps Bardin native; removed from picker |
| dr_shield_axe | Axe & Shield | ✅ | native fall-through; capture-confirmed v0.12.139-dev → excluded from chooser |
| dr_1h_throwing_axes | Throwing Axes | 📋 | decided `to_1h_mace` |
| dr_drake_pistol | Drakefire Pistols | 📋 | decided `to_repeating_handgun` + **offhand hide** (model-sub queue) |
| dr_drakegun | Drakegun | 📋 | decided `to_blunderbuss` |
| dr_steam_pistol | Masterwork Pistol | 📋 | decided `to_repeating_handgun` |
| dr_deus_01 | Trollhammer Torpedo | 📋 | decided `to_blunderbuss` |
| we_1h_axe | Kerillian: 1H Axe | ✅ | **[Working] — BAKED v0.12.156-dev** career-scoped `_3p_template_remaps.we_one_hand_axe_template.es_` (Kruber native 1H Axe, mostly identity); `we_ = false` keeps Kerillian native; removed from picker |
| we_2h_axe | Kerillian: Glaive | ✅ | **[Working] — BAKED v0.12.156-dev** career-scoped `_3p_template_remaps.two_handed_axes_template_2.es_` (Empire Greathammer; grip offset already set v0.12.152); `we_ = false` keeps Kerillian native; removed from picker |
| we_dual_wield_daggers / _swords / _sword_dagger | Elf duals ×3 | ✅ | **[Working] — BAKED v0.12.156-dev** career-scoped `_3p_template_remaps.dual_wield_daggers_template_1.es_` / `.dual_wield_swords_template_1.es_` / `.dual_wield_sword_dagger_template_1.es_` (Empire Mace & Sword); `we_ = false` keeps Kerillian native; removed from picker |
| we_shortbow / we_shortbow_hagbane | Shortbow / Hagbane | 📋 | crash-safety net only (j_hips); **TODO #31**: proper model sub → Empire Longbow |
| we_javelin | Javelin | ❓ | EXPERIMENTAL, target TBD |
| we_life_staff | Deepwood Staff | ❓ | PENDING user decision (DECISIONS:226) |
| we_crossbow_repeater | Repeater Crossbow | 🧊 | **CRASH FIXED v0.12.139-dev** — empty-wield reload fired the unregistered `_elf`/`_elf_noammo` not-loaded/no-ammo wields → nil NetworkLookup.anims id → RPC-packer fatal (network game). Now patches `wield_anim_not_loaded_career`/`wield_anim_no_ammo_career` → `to_repeating_handgun`/`_noammo` (registered + Kruber-authored). Loaded stance SET=`to_repeating_handgun` (per-attack still pending) |
| wh_dual_hammer | WP Dual Skullsplitters | ✅ | **[Working] — BAKED v0.12.156-dev** career-scoped `_3p_template_remaps.dual_wield_hammers_priest_template.es_` (Empire Mace & Sword); `wh_ = false` keeps Saltzpyre/WP native; removed from picker |
| wh_2h_hammer | WP Greathammer (Reckoner) | ✅ | **[Working] — BAKED v0.12.151-dev** career-scoped `_3p_template_remaps.two_handed_hammer_priest_template.es_` (Empire Greathammer); `wh_ = false` keeps Saltzpyre/WP native; removed from picker |
| wh_fencing_sword | Rapier | 📋 | MODEL-SUB queue (hide off-hand pistol, route `to_1h_sword_shield`); NOT a plain chooser row — separate later pass |
| wh_flail_shield | WP Flail & Shield | ✅ | **[Working] — BAKED v0.12.156-dev** career-scoped `_3p_template_remaps.one_handed_flail_shield_template.es_` (Empire Mace & Shield); `wh_ = false` keeps Saltzpyre/WP native; removed from picker |
| wh_hammer_book | WP Skullsplitter & Tome | 📋 | MODEL-SUB queue (hide tome, plain Skullsplitter mesh, native 1H-mace anims); NOT a plain chooser row — separate later pass |
| wh_crossbow_repeater | Volley Crossbow | 📋 | decided `to_repeating_handgun`; uses REGISTERED `to_repeating_crossbow`/`_noammo` not-loaded wields (no crash, unlike the elf `we_crossbow_repeater`) — decided-not-wired |
| wh_deus_01 | Griffon-foot | 📋 | decided `to_repeating_handgun` + **repeater-handgun MODEL sub + offhand hide, mirror Brace** (model-sub queue) |
| bw_1h_mace | Sienna: Mace | ✅ | **[Working] — BAKED v0.12.150-dev** career-scoped `_3p_template_remaps.one_handed_hammer_wizard_template_1.es_` (Empire Greathammer); `bw_ = false` keeps Sienna native; removed from picker |
| bw_dagger | Sienna: Dagger | ✅ | **[Working] — BAKED v0.12.149-dev** career-scoped `_3p_template_remaps.one_handed_daggers_template_1.es_` (Empire 1H Sword); removed from picker |
| bw_flame_sword | Sienna: Flame Sword | ✅ | **[Working] — BAKED v0.12.149-dev** career-scoped `_3p_template_remaps.flaming_sword_template_1.es_` (Empire 1H Sword); removed from picker |
| bw_ghost_scythe | Ensorcelled Reaper | ✅ | **[Working] — BAKED v0.12.150-dev** career-scoped `_3p_template_remaps.staff_scythe.es_` (Empire Greathammer); `bw_ = false` keeps Sienna native. **Grip offset BAKED**: `_weapon_grip_offsets.bw_ghost_scythe.es_ = {0,0,6}` (es_-scoped, 3P-only) via the **DURABLE per-frame re-apply path** `_DURABLE_GRIP_OFFSETS` (v0.12.151-dev bumped 0.569→6 — the one-shot was stomped in-game; see OFFSETS.md); removed from picker + `_NEEDS_OFFSETS` |
| bw_skullstaff_* ×5, bw_necromancy_staff, bw_deus_01 | Sienna staves ×7 | 📋 | all decided `to_2h_hammer`; user will UNSET some actions via picker |
| wh_1h_falchion | Falchion | — | CWV-managed on Kruber — wt skips |

## Receiver: KERILLIAN (we_waywatcher / we_maidenguard / we_shade / we_thornsister)

All `we_*` natives 🔁 (~14 keys).

| weapon_key | Display name | Status | Strategy / notes |
|---|---|---|---|
| es_2h_sword / wh_2h_sword | Empire/WH Greatsword | ✅ | Invert redirect + 8-entry remap + grip −0.085 Z |
| es_deus_01 | Kruber: Spear & Shield | ✅ | deus→spear_shield route |
| es_halberd / es_2h_heavy_spear | Halberd / Tuskgor Spear | ✅ | `to_polearm→to_spear` override + suffix |
| wh_2h_billhook | Billhook | ✅ | we_→`to_spear` override (matches decided target) |
| es_1h_flail | Empire Flail | ✅ | universal + heavy fixes |
| wh_1h_falchion | Falchion | ✅ | template `_default` remap |
| bw_1h_crowbill | Crowbill | ✅ | remap + scale |
| dr_2h_axe | Greataxe | ✅ | `_default` remap + scale |
| dr_1h_hammer | Bardin: 1H Hammer | 🧊 | wired `to_1h_hammer→to_1h_sword` (phantom-event fix) but DECISIONS:289 says target we_1h_axe — **review mismatch** |
| wh_1h_axe + native axes | 1H axes | 🔁 | native `to_1h_axe` |
| es_mace_shield / es_sword_shield / es_sword_shield_breton | Empire shield combos | 🔧 | native shield vocab TRUE on Kerillian; decided we_1h_spears_shield not wired — native may suffice, verify |
| es_2h_hammer | Greathammer | 📋 | decided `we_2h_axe→to_2h_axe` (`to_2h_hammer` FALSE on Kerillian) |
| es_2h_sword_executioner / es_bastard_sword | Executioner / Bret. Longsword | 🔧 | wield covered by greatsword redirect; per-action only if same template — verify |
| es_dual_wield_hammer_sword | Mace & Sword | 📋 | decided we_dual_wield_sword_dagger |
| es_blunderbuss / es_handgun / es_repeating_handgun | Kruber ranged ×3 | 📋 | decided `we_crossbow_repeater→to_repeating_crossbow_elf` |
| wh_1h_hammer | Saltz: 1H Hammer | 🔧 | wired to_1h_sword fix; decided we_1h_axe — review |
| wh_2h_hammer | Saltz: 2H Hammer | 📋 | decided we_2h_axe |
| wh_dual_hammer | Dual Hammers | 📋 | decided we_dual_wield_swords |
| wh_dual_wield_axe_falchion | Axe & Falchion | 📋 | decided we_dual_wield_sword_dagger |
| wh_fencing_sword | Rapier | 📋 | decided we_1h_sword |
| wh_brace_of_pistols | Brace of Pistols | 📋 | **2-target port**: MODEL = wh_repeating_pistols mesh + ANIMS = to_repeating_crossbow_elf (model-sub queue) |
| wh_deus_01 | Griffon-foot | 📋 | same 2-target pattern + offhand hide (model-sub queue) |
| wh_crossbow / wh_crossbow_repeater / wh_repeating_pistols | Saltz ranged ×3 | 📋 | decided we_crossbow_repeater targets; repeater xbow partially helped by global redirect; plain crossbow likely idle no-op. #441 mirror v0.12.212-dev baked we_* `wield_anim_career_3p = to_repeating_crossbow_elf` on wh_crossbow_repeater (keep-preview idle) [untested] |
| wh_flail_shield / wh_hammer_book / wh_hammer_shield | WP combos | 🔧 | `to_1h_hammer_shield` TRUE on Kerillian — verify native; decided we_1h_spears_shield as fallback |
| dr_2h_cog_hammer / dr_2h_pick | Cog Hammer / Pickaxe | 📋 | decided we_2h_axe |
| dr_dual_wield_axes / dr_dual_wield_hammers | Bardin duals | 📋 | decided we_dual_wield_swords |
| dr_shield_axe | Axe & Shield | 📋 | decided we_1h_spears_shield |
| dr_1h_throwing_axes | Throwing Axes | 📋 | decided `we_javelin→to_javelin` |
| dr_crossbow / dr_deus_01 / dr_drake_pistol / dr_drakegun / dr_rakegun / dr_steam_pistol | Bardin ranged ×6 | 📋 | all decided we_crossbow_repeater; drake_pistol needs offhand hide |
| bw_1h_flail_flaming | Flaming Flail | 🔧 | wield redirect wired in v0.12.119 (career-agnostic, covers Kerillian too) — needs in-game verify; decided per-action target we_1h_sword still 📋 |
| bw_dagger / bw_flame_sword | Dagger / Flame Sword | 📋 | decided we_1h_sword |
| bw_ghost_scythe + staves ×7 | Reaper + staves | 📋 | all decided `we_2h_axe→to_2h_axe` |

## Receiver: SALTZPYRE non-WP (wh_captain / wh_bountyhunter / wh_zealot)

All `wh_*` natives 🔁 (~14 keys).

| weapon_key | Display name | Status | Strategy / notes |
|---|---|---|---|
| es_longbow | Empire Longbow | ✅ | **Model sub → Crossbow** (+bolt; mission + preview) |
| we_longbow | Elf Longbow | ✅ | Model sub → Crossbow (shared helpers, v0.12.44) |
| we_spear | Elf Spear | ✅ | Patcher wh→`to_2h_billhook` + 12-entry remap + force-fires |
| es_2h_heavy_spear | Tuskgor Spear | ✅ | same billhook route (push follow-up untested) |
| es_halberd | Halberd | ✅ | patcher wh→to_2h_billhook |
| we_2h_sword | Elf Greatsword | ✅ | wh→`to_1h_sword` + template remap (falchion anims) |
| we_1h_sword | Elf Sword | ✅ | key remap + scale 1.15 |
| es_1h_flail | Empire Flail | ✅ | native-wielder push fix (incl. vanilla bugfix) |
| bw_1h_crowbill | Crowbill | ✅ | `_default` remap |
| dr_2h_axe | Greataxe | ✅ | `_default` remap + scale |
| we_crossbow_repeater | Elf Repeater Crossbow | ✅ | redirect to `to_repeating_crossbow` ("should work almost perfectly"); #441 v0.12.212-dev baked wh_* `wield_anim_career_3p = to_repeating_crossbow` (keep-preview idle was wrong; in-mission redirect never covered the previewer) |
| we_1h_spears_shield | Elf Spear & Shield | 🧊 | live = legacy sword&shield suffix route; DECISIONS SHO7 retargets to `wh_dual_wield_axe_falchion` — **conflict, not wired** |
| es_1h_mace / es_1h_sword / we_1h_axe | 1H family | 🔁 | universal vocab fall-through |
| es_2h_sword_executioner | Executioner | ✅ | BAKED wh_ v0.12.201-dev (#160) → Saltzpyre 2H Sword |
| es_bastard_sword | Bret. Longsword | 🔧 | **BAKED v0.12.213-dev (#519)** `_3p_template_remaps.bastard_sword_template.wh_` (Saltzpyre 2H Sword, 14 picks incl. `swap_charge_stance`); wired-unverified |
| es_2h_hammer / dr_2h_cog_hammer / dr_2h_pick / bw_1h_mace / bw_ghost_scythe | 2H-blunt family ×5 | 🔧 | **BAKED v0.12.213-dev (#519)** career-scoped wh_ → WP Greathammer (`two_handed_hammers_template_1` / `two_handed_cog_hammers_template_1` / `two_handed_picks_template_1` / `one_handed_hammer_wizard_template_1` / `staff_scythe`); wired-unverified |
| dr_2h_hammer | Bardin 2H Hammer | 🔧 | NOT in batch-2 — `to_2h_hammer` TRUE on Saltz, fall-through expected, per-action unverified |
| we_2h_axe | Glaive | 📋 | decided wh_2h_hammer (user override) |
| es_dual_wield_hammer_sword | Mace & Sword | 📋 | decided wh_dual_hammer |
| dr_dual_wield_axes | Bardin Dual Axes | ✅ | BAKED wh_ v0.12.188/.203 (`dual_wield_axes_template_1.wh_` → Dual Axe & Falchion) |
| dr_dual_wield_hammers | Bardin Dual Hammers | 📋 | batch-2 picker row live (→ WP Dual Hammers) but tester left ALL picks unset (#519) — not baked, still queued |
| we_dual_wield_daggers / _swords / _sword_dagger | Elf duals ×3 | 📋 | decided wh_dual_wield_axe_falchion |
| es_blunderbuss / es_handgun | Blunderbuss / Handgun | 🔧 | Saltz HAS `to_blunderbuss`/`to_handgun` per probe — may fall through natively despite decided wh_crossbow; verify before wiring |
| es_repeating_handgun | Repeater Handgun | 📋 | decided wh_repeating_pistols |
| we_shortbow / we_shortbow_hagbane | Shortbow / Hagbane | 📋 | **model sub → Volley Crossbow unit** (user override; model-sub queue) |
| we_deus_01 | Moonfire Bow | 📋 | decided wh_crossbow (AOE/puff stat hooks already exist separately) |
| dr_1h_axe / dr_1h_hammer | Bardin 1H | 🔁 | fall-through |
| dr_1h_throwing_axes | Throwing Axes | 📋 | decided wh_1h_axe ("will likely be goofy") |
| dr_rakegun / dr_drakegun | Grudge-Raker / Drakegun | 📋 | decided wh_crossbow_repeater |
| dr_drake_pistol | Drakefire Pistols | 📋 | decided wh_brace_of_pistols |
| dr_steam_pistol | Masterwork Pistol | 📋 | decided wh_repeating_pistols |
| dr_deus_01 | Trollhammer | 📋 | decided wh_crossbow |
| dr_shield_axe / es_mace_shield / es_sword_shield / es_sword_shield_breton | shield combos ×4 | 🔧 | **BAKED v0.12.213-dev (#519)** career-scoped wh_ → Dual Axe & Falchion (`one_hand_axe_shield_template_1` / `one_handed_hammer_shield_template_1` / `one_handed_sword_shield_template_1` / `_2`); right-hand weapon render only, **shield-offhand model dispatcher still pending** (Wave 3, model-sub queue); wired-unverified |
| shield combos ×3 (dr_shield_hammer, es_deus_01, we_1h_spears_shield) | — | 📋 | SHO decided `wh_dual_wield_axe_falchion` + **shield-offhand model dispatcher** (Wave 3, model-sub queue); es_deus_01 currently on legacy suffix route |
| bw_dagger | Sienna Dagger | 📋 | decided wh_fencing_sword |
| bw_flame_sword | Flame Sword | 📋 | decided wh_1h_falchion |
| staves ×8 (bw_skullstaff_* ×5, bw_necromancy_staff, bw_deus_01, we_life_staff) | — | 📋 | all decided wh_1h_falchion — needs cast/charge/beam wield-vocab synthesis |
| we_javelin | Javelin | 📋 | decided wh_1h_axe (no Saltz thrown vocab) |

## Receiver: BARDIN (dr_ranger / dr_ironbreaker / dr_slayer / dr_engineer)

All `dr_*` natives 🔁 (~15 keys; duals get the non-Slayer redirect).

| weapon_key | Display name | Status |
|---|---|---|
| we_1h_sword | Elf Sword | ✅ remap + scale 1.10 + grip |
| es_1h_sword | Empire Sword | ✅ dr_ key remap (3-heavy chain fix) + grip |
| wh_1h_falchion | Falchion | ✅ dr_ remap (heavy variants differentiated) |
| bw_1h_crowbill | Crowbill | ✅ dr_ remap + scale 1.05 |
| es_handgun | Empire Handgun | 🔁 native `to_handgun` |

## Receiver: WARRIOR PRIEST (wh_priest)

Melee-only by hard rule (rt check `wh_priest_no_bows` + picker filter). All 7
entries ✅/🔁 (native WP vocab + priest-specific redirects). The only
cross-prefix row is es_1h_flail ✅.

## Receiver: SIENNA (bw_adept / bw_scholar / bw_unchained / bw_necromancer)

13 entries, all `bw_*` native 🔁. **Zero cross-character ports — user to decide**
(DECISIONS:634-638). A receiver-side redirect (`to_1h_axe→to_1h_sword`) is
already staged for when ports land.

---

## Model-substitute queue (Wave 3 — all decided, none wired)

The shipped pattern is hardcoded per port (force-load + dispatcher predicate +
mission/preview helpers ×2). These are waiting; consider generalizing into a
data-driven `{source_key, career_prefix, target_unit, target_template, ammo?,
offhand_hide?}` table before wiring #3+ (3 shipped ports already duplicate the
shape):

1. Griffon-foot → repeater-handgun mesh on Kruber (+offhand hide) — DECISIONS:153
2. Brace + Griffon-foot → repeater-pistol mesh on Kerillian — DECISIONS:332/334
3. Shortbow/Hagbane → volley-crossbow unit on Saltzpyre — DECISIONS:517-518
4. Elf bows → Empire Longbow on non-elves — TODO #31
5. Drakefire Pistols offhand-hide (Kruber + Kerillian) — DECISIONS:80/296
6. Shield-offhand dispatcher for SHO1-7 on Saltzpyre — DECISIONS:611-616
7. Brace illusion-matched skin swap (resolver exists, never wired into the swap hooks)

## Known tooling gaps (tracked for the Wave-2 pass)

- Hold-pose tuner: mission-only live-apply, single global slider set (no
  per-(career,weapon)/per-hand memory — task #24), dump shape not directly
  consumed by any wt table.
- No live tuning surface for `_weapon_scale_overrides` / `_weapon_grip_offsets`
  (source-edit only; applied at equipment-create, so live mutation needs
  re-equip).
- Picker has closed-vocabulary curation for only 6 decided targets
  (`_WIELD_EVENT_TO_TARGET`); the ~100 📋 rows fall back to broad receiver
  vocab where picks can silently produce invisible playback (chain-state
  problem, DEVELOPMENT.md).
- ~~No `/wt_coverage` in-game probe~~ — **shipped v0.12.119**: `/wt_coverage`
  walks the current character's ports and logs per-port FULL/PARTIAL/NONE
  authored-ness (`[wt:coverage]` lines). Run it once per character and paste the
  log to refresh this file's statuses. Caveat: authored ≠ visibly plays in
  chain states; 🔧 rows still need an eyeball pass.
