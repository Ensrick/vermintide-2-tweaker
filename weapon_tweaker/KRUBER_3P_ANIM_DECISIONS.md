# Kruber 3P cross-character weapon anim decisions — live capture (2026-06-23)

Streaming capture of the user's in-game testing of cross-character weapons on **Kruber**.
`ANIMATION_COVERAGE.md` is the source of truth; this is the **pending-merge log** kept
separate while the anim-picker workflow (`wspgmezko`) is mid-edit (avoids file collision).
Reconcile into `ANIMATION_COVERAGE.md` + wire the picker once that workflow lands.

## ⚠️ OPEN ISSUES (updated 2026-06-23)

- **🔴 Picker picks NOT applying in 3P (user 2026-06-23):** user picks per-attack anims (e.g. Bardin's War Pick on Kruber, all inserted) but the rendered 3P anim doesn't change. The pick writes `sub.anim_event_3p` on the live template, but that apparently doesn't reach what the engine reads at attack time. Dropdown OPTIONS are confirmed correct (byte-exact target-set attack anims). Investigation-first fix dispatched (`wkg3xs49p`) — trace the real cross-char 3P-anim read-site before changing the write target + handle equip-time caching. **KEY CLUE (user 2026-06-23): game RESTART + CHARACTER CHANGE make NO difference** → rules out a simple equip-time cache (a restart would clear that); points to either (a) WRONG write target — the engine plays the cross-char redirect's renamed event and ignores the picker's `anim_event_3p`, or (b) stored picks are never re-applied to the template on reload. Fix must hit the engine's actual read-site AND re-apply on load. **FIX SHIPPED wt 0.12.144** (`wkg3xs49p`): write target was already correct (`anim_event_3p` on live `Weapons[tpl].actions`, which the engine reads per-attack via `current_action_settings`); fix adds (a) `MechanismOverrides.recursive_cleanup` cache-bust so override templates re-resolve, (b) boot-replay `reapply_stored_picks()` (weapon_tweaker.lua:5462 install), (c) `_try_force_rewield` for immediate refresh on the equipped weapon, (d) confirmed `_WEAPON_ATTACKS.dr_2h_pick` matches the 12 template `anim_event` strings verbatim (n>0). Verify clean, 3P-only. ⚠️ **0.12.144 FAILED in-game (user 2026-06-24):** picks PERSIST (dropdowns filled after restart = boot-replay works) but STILL no 3P change on pickaxe. Structural "write reaches engine read-site" now WRONG 2×. → **INSTRUMENTING** (`wt-apply-instrument` → 0.12.145): log `[wt:apply]` (template + writes + count) and `[wt:play]` (anim_event_3p engine reads + FINAL event after wt's `Unit.animation_event` redirect funnel). **PRIME SUSPECT:** the runtime `_anim_redirect`/`_career_anim_redirect`/`_suffix_career_map` funnel (weapon_tweaker.lua ~1229) RENAMES the picked event at play-time, silently overriding it. Diagnose from the user's attack log, not another structural guess. **0.12.145 SHIPPED (instrumented).** Agent REFUTED the funnel-override (pickaxe wield `to_2h_hammer` isn't a `_3p_remap_triggers` key; no `_3p_template_remaps`/`_3p_key_remaps` entry → event fires unchanged) AND found the 0.12.144 cache-bust is a NO-OP for the pickaxe (`two_handed_picks_template_1` has no `mechanism_overrides`). So the loss is UPSTREAM: either `n==0` write (stale `_WEAPON_ATTACKS` source-string mismatch — log dumps live vocab) or `has_anim=false` (Kruber body lacks the picked clip). Awaiting user's pickaxe-swing log: `[wt:apply]`(tpl,n) + `[wt:play]`(is_picked_3p_value, has_anim, FINAL-renamed?). **🎯 LOG VERDICT (0.12.145, user-swung dr_2h_pick): ZERO `[wt:apply]` lines all session + EVERY `[wt:play]` shows `picks_set={}` (EMPTY), `is_picked_3p_value=false`, `has_anim=true`, FINAL unchanged.** ROOT CAUSE pinned: picks ARE in VMF settings (dropdowns display them) but the apply path's `picks_set` is NEVER populated from settings → `reapply_stored_picks` enumerates/writes NOTHING. Clips exist (has_anim=true) + funnel innocent (FINAL unchanged) — pure load-from-settings gap, upstream of all the cache/refresh/persistence "fixes". Fix dispatched (`wt-picks-load-fix` → 0.12.147; trace dropdown WRITE setting_id vs reapply READ id + boot-timing of the catalog enumeration). Rides with the preview-pose fix. **Deploy AND upload when done.** **✅ FIXED + SHIPPED 0.12.147 (build+deploy+upload).** ROOT CAUSE: `mod:dofile` returns a FRESH module per call (NOT a singleton) → the SCRIPT instance's `_setting_index` was empty (only the DATA instance's `build_widget_tree` populated it) → `reapply_stored_picks` iterated nothing → zero writes. Fix: `_ensure_setting_index_built()` (idempotent, guarded) called in `reapply_stored_picks` + `on_setting_changed`. Memory [[reference_vmf_dofile_not_singleton]]. 0.12.147 ALSO carries the Elf Greatsword inventory-preview wield-pose fix. ✅ **CONFIRMED RESOLVED (log 2026-06-24, wh_2h_hammer tested): `[wt:apply] n=1` writes fired + `[wt:play] is_picked_3p_value=true` + populated `picks_set`. Picks apply. No crashes/ScriptErrors in the log.** (Minor benign: gut repeatedly logs `LA atlas package not resident … skipping pin (force-materialize crash guard)` on menu-enter — guard working, but a gut icon-pin wants an LA atlas that isn't resident; investigate whether the pin is needed.)

- **✅ gut Mod Tweaker dropdowns — FIXED (gut 0.2.75):** NOT an options-read bug (gut reads `node.options`/`option.text`/`option.value` exactly like VMF) — a **nesting-depth** bug. The picker is 3 levels deep (checkbox → set-group → dropdown); gut's gear-drill only rendered ONE level of children → depth-3 dropdowns were unreachable → "?" empty rows. Fixed via shared `plan_drill_children` (walks the whole subtree w/ group-expand rules). Restart → dropdowns populate.
- **Picker tags wrong place:** everything in the picker needs animations by definition → REMOVE the `[Needs Animations]` tag from the PICKER. Tags belong on **WEAPON AVAILABILITY**: fully-functional vs what-it-needs AND the redirect target (e.g. `[Greathammer]`). Dispatched (`wby4oz1j9`).
- **Naming — CHARACTER names:** Bardin / Sienna / Saltzpyre / Kruber / Kerillian (like availability), NOT race names ("Dwarf Pickaxe" → "Bardin Pickaxe"). Dispatched (`wby4oz1j9`).
- **Picker shows untested weapons:** it auto-lists all non-confirmed (e.g. Beam Staff, never flagged) — should list ONLY explicitly `[Needs Animations]`-flagged weapons. Dispatched (`wby4oz1j9`).
- **🔴 Scrollbar — STILL BROKEN (I misread the data; user is right):** the THUMB draws at FULL track height (`thumb_frac` clamps to 1.0 when content fits → `thumb_px=760` = whole column), in GREY `{210,210,210}` (wrong — should be native tan), covering the track so there's **NO visible backdrop**, ALWAYS max size. It also draws even when nothing scrolls (the draw is NOT gated on `max_scroll>0`/`will_draw`). FIX: (1) HIDE when content fits (`max_scroll<=0`) — the draw-gate was ALREADY in 0.2.75 (the full grey column was the PRE-gate 0.2.74 state); (2) proportional thumb (already correct, `thumb_frac~0.82` on overflow); (3) thumb color grey `{210}` → **native tan `{160,146,101}`** — THE actual fix this version. **REAL CAUSE (0.2.76 probe: thumb `style_size={8,760}` = ALWAYS full track):** the thumb's proportional-sizing `offset_function` never runs because its pass isn't `local_offset` — memory `reference_vt2_offset_function_local_offset_only`, the SAME bug that burned the gut SLIDER 3×. Thumb always full → no room to drag → can't scroll. Tan color + draw-gate (0.2.76) are correct; sizing is the bug. FIX: drive the thumb size/position via a `local_offset` pass (native-slider pattern). **SHIPPED gut 0.2.77** — confirmed the offset_function WAS on a `rect` pass (so it never ran); now on `local_offset` (`_mod_tweaker_definitions.lua:1201`). Probe logs `_resolved_thumb_h` (<760 in-game = fix fired). Awaiting verify on an OVERFLOWING menu (thumb should be proportional + draggable).
- **Scrollbar 0.2.77 result (user-tested):** thumb DOES resize now ✅ (local_offset fix worked). REMAINING: (a) thumb POSITION inverted — at scroll=0 (top of menu) the thumb sits at the track BOTTOM; scrolling down moves it further down + OVERFLOWS past the menu bottom. Should track top→bottom, clamped to track bounds. (b) track color `{70,70,70}` is FABRICATED — must use the REAL vanilla scrollbar track/thumb colors. FIX (`gut-scrollbar-fix3` cont. → 0.2.78): matched `UIWidgets.create_scrollbar` — track → vanilla `{5,5,5}` (was fabricated `{70,70,70}`), thumb formula flipped `end_position*(1-scroll_value)` clamped to `[0,end_position]` (scroll=0→top, can't overflow); probe logs thumb world-Y. **✅ RESOLVED — user-confirmed good in-game (0.2.78):** track vanilla `{5,5,5}`, thumb proportional + correctly positioned (top→bottom) + draggable. (Workshop upload hit Steam `0x9`; re-attempting — fix is live via local deploy regardless; next gut upload carries it if needed.)
- **✅ Picker SIMPLIFY — SHIPPED wt 0.12.143:** set-chooser dropdown REMOVED (set hardcoded per weapon in `_WEAPON_SET` A–E); per-attack dropdown options HARDCODED from `_SET_VOCAB` (no dynamic `_live_target_template_for` — grep-clean); all 15 flagged weapons have populated attacks (9–16 each); 5 set vocabs byte-exact vs decompiled templates (A=Greathammer, B=Mace&Sword, C=Empire 1H Sword, D=Mace&Shield, E=WH 1H Axe). 3P-only. Apply writes `anim_event_3p` only.
- **✅ Redirect-crash audit (`wt-redirect-audit`, read-only): CLEAN — no latent redirect crashes.** All networked-path anim values (picker `_SET_VOCAB`, the 3 `*_ANIM_REMAP_3P` tables) are registered; unregistered targets are wield/melee events on the NON-networked path → no-op, never crash. Only crash class (unregistered event → ammo reload-send / `_play_3p_anim`) was the elf repeater-crossbow, already fixed (`weapon_tweaker.lua:2453-2482`). Tracking note (not urgent): `_anim_redirect` maps `to_repeating_crossbow → to_repeating_crossbow_elf` (unregistered) at `weapon_tweaker.lua:484-485` — safe today (non-networked); flag before any future `_anim_redirect` edit could reach an ammo-send on a non-elf wielder.
- **Elf Greatsword (`we_2h_sword`) on Kruber — inventory-PREVIEW missing wield pose (user 2026-06-24):** in-mission 3P CONFIRMED working, but the character-screen preview model holds it in a default/rest pose (no wield stance). Preview-path-only (`MenuWorldPreviewer`) — the cross-char wield pose isn't applied in the preview path. Investigate+fix dispatched (`wgrpii7qo`).
- **✅ Resolved — v0.12.141:** picker names = weapon TYPE (not cosmetic illusion); overflow gone; dropdowns populate in VMF (gut blocked, above); Saltzpyre Flail tagged.
- **✅ Resolved — v0.12.142:** picker status-tags REMOVED; tags moved to **Weapon Availability** with redirect target (`[Needs Animations → Greathammer]`); CHARACTER names ("Bardin Pickaxe"); picker lists ONLY `[Needs Animations]`-flagged weapons (Beam Staff `bw_skullstaff_beam` excluded, War Pick present). *(Open: gut dropdowns `w71bxi2am`, scrollbar queued behind it.)*

## ✅ BAKED (v0.12.149-dev) — permanent career-scoped Kruber defaults

User confirmed finished tuning: **Pickaxe, Dual Axes, Sienna's Fire Sword, Sienna's Dagger.** Full `source_event → picked anim_event_3p` sets, pulled verbatim from `[wt:play] picks_set` (identity pairs = kept default). **These four are now BAKED PERMANENTLY** — they ship to every friend + subscriber without the picker.

**Mechanism (v0.12.149-dev):** baked CAREER-SCOPED into `_3p_template_remaps`
(`weapon_tweaker.lua`), NOT as a shared-template `anim_event_3p` write. Each template
carries NO authored `anim_event_3p` natively, so `weapon_unit_extension.lua:512`
(`anim_event_3p or event`) fires the source `anim_event` on EVERY wielder's own 3P body
(`:652`). A shared write would corrupt the NATIVE owner's 3P (Bardin pickaxe/dual-axes,
Sienna fire-sword/dagger). The bake adds an `es_`-keyed remap (Kruber careers only) with
the owner prefix (`dr_`/`bw_`) set to `false` → `_resolve_template_remap` returns nil for
the native owner → native plays UNTOUCHED. Same native-owned precedent as
`two_handed_billhooks_template` (`wh_ = false`). Consumed at the `Unit.animation_event`
hook (3P body only). The 4 are REMOVED from `_NEEDS_ANIMS.kruber` (so the picker no
longer offers them) and added to `_CONFIRMED.kruber` (Availability tag now reads
`[Working]`). The `[wt:apply]`/`[wt:play]` instrumentation + the picker for the REMAINING
weapons are unchanged.

| Baked weapon | weapon_key | Template (`_3p_template_remaps` entry) | Renders as |
|---|---|---|---|
| Bardin's Pickaxe | `dr_2h_pick` | `two_handed_picks_template_1.es_` | Empire Greathammer |
| Bardin's Dual Axes | `dr_dual_wield_axes` | `dual_wield_axes_template_1.es_` | Empire Mace & Sword |
| Sienna's Fire Sword | `bw_flame_sword` | `flaming_sword_template_1.es_` | Empire 1H Sword |
| Sienna's Dagger | `bw_dagger` | `one_handed_daggers_template_1.es_` | Empire 1H Sword |
| Sienna's Mace | `bw_1h_mace` | `one_handed_hammer_wizard_template_1.es_` | Empire Greathammer |
| Necromancer Scythe | `bw_ghost_scythe` | `staff_scythe.es_` (+ DURABLE `_weapon_grip_offsets.es_ = {0,0,6}`, v0.12.151-dev) | Empire Greathammer |
| Warrior Priest / Saltzpyre Greathammer | `wh_2h_hammer` | `two_handed_hammer_priest_template.es_` (v0.12.151-dev) | Empire Greathammer |
| Bardin Coghammer | `dr_2h_cog_hammer` | `two_handed_cog_hammers_template_1.es_` (v0.12.151-dev, all-identity) | Empire Greathammer |

The verbatim `source_event → picked anim_event_3p` sets (kept as the bake-table provenance):

- **Pickaxe `dr_2h_pick`** (→ Greathammer): `attack_push→attack_push, attack_swing_charge_left_down→attack_swing_charge_left, attack_swing_charge_left_down_pose→attack_swing_charge, attack_swing_charge_right_down→attack_swing_charge_right, attack_swing_down_left→attack_swing_down_left, attack_swing_down_left_axe→attack_swing_down_left, attack_swing_down_right→attack_swing_down_right, attack_swing_down_right_axe→attack_swing_down_right, attack_swing_left→attack_swing_left, attack_swing_left_diagonal→attack_swing_left_diagonal, attack_swing_right_diagonal→attack_swing_heavy_right, parry_pose→parry_pose`
- **Dual Axes `dr_dual_wield_axes`**: `attack_push→attack_push, attack_swing_charge_diagonal→attack_swing_charge_left, attack_swing_charge_left→attack_swing_charge_left, attack_swing_charge_right→attack_swing_charge_right, attack_swing_down→attack_swing_down, attack_swing_heavy→attack_swing_heavy_left_diagonal, attack_swing_heavy_left_diagonal→attack_swing_heavy_left_diagonal, attack_swing_heavy_right→attack_swing_heavy_right_diagonal, attack_swing_left→attack_swing_left_diagonal, attack_swing_left_diagonal→attack_swing_left, attack_swing_right→attack_swing_right_diagonal, attack_swing_right_diagonal→attack_swing_right, parry_pose→parry_pose`
- **Sienna's Fire Sword `bw_flame_sword`**: `attack_push→attack_push, attack_swing_charge→attack_swing_charge_left, attack_swing_charge_right→attack_swing_charge_right_pose, attack_swing_heavy→attack_swing_heavy, attack_swing_left→attack_swing_left_diagonal, attack_swing_left_diagonal→attack_swing_left_diagonal, attack_swing_right_diagonal→attack_swing_right_diagonal, attack_swing_right_spell→attack_swing_right, attack_swing_stab→attack_swing_down, parry_pose→parry_pose`
- **Sienna's Dagger `bw_dagger`**: `attack_push→attack_push, attack_swing_charge→attack_swing_charge_left, attack_swing_charge_left→attack_swing_charge_right_pose, attack_swing_heavy→attack_swing_heavy, attack_swing_heavy_right→attack_swing_heavy_right, attack_swing_left→attack_swing_left_diagonal, attack_swing_left_diagonal→attack_swing_left_diagonal, attack_swing_right_diagonal→attack_swing_right_diagonal, attack_swing_stab→attack_swing_down, parry_pose→parry_pose`
- **Sienna's Mace `bw_1h_mace`** (→ Greathammer, v0.12.150-dev): `attack_push→attack_push, attack_swing_charge_left_diagonal→attack_swing_charge, attack_swing_charge_left_pose→attack_swing_charge_left, attack_swing_charge_right_pose→attack_swing_charge_right, attack_swing_down→attack_swing_down_left, attack_swing_heavy_down→attack_swing_down_left, attack_swing_heavy_left_up→attack_swing_heavy, attack_swing_heavy_right_up→attack_swing_heavy_right, attack_swing_left→attack_swing_left, attack_swing_left_diagonal→attack_swing_left_diagonal, attack_swing_left_diagonal_last→attack_swing_left_diagonal, attack_swing_right_diagonal→attack_swing_down_right, parry_pose→parry_pose`
- **Necromancer Scythe `bw_ghost_scythe`** (→ Greathammer, v0.12.150-dev; **+ DURABLE 3P grip offset +6 Z, es_-scoped, v0.12.151-dev** — bumped from +0.569 and moved to the per-frame re-apply path because the one-shot was stomped in-game, see OFFSETS.md): `attack_push→attack_push, attack_swing_charge_left→attack_swing_charge_left, attack_swing_charge_left_diagonal→attack_swing_charge_left, attack_swing_charge_right→attack_swing_charge_right, attack_swing_heavy→attack_swing_heavy, attack_swing_heavy_left_diagonal→attack_swing_heavy, attack_swing_heavy_right→attack_swing_heavy_right, attack_swing_left→attack_swing_left, attack_swing_left_diagonal→attack_swing_down_left, attack_swing_left_diagonal_last→attack_swing_down_left, attack_swing_right→attack_swing_heavy_right, attack_swing_up_right→attack_swing_down_right, parry_pose→parry_pose, special_action→attack_swing_charge, special_action_02→attack_swing_down_left` (the two scythe specials have no SET A twin — mapped to nearest)
- **Warrior Priest / Saltzpyre Greathammer `wh_2h_hammer`** (→ Greathammer, v0.12.151-dev; native owner `wh_ = false`): `attack_push→attack_push, attack_slam→attack_push, attack_slam_charge→attack_swing_down_right, attack_swing_charge→attack_swing_charge, attack_swing_charge_right→attack_swing_charge_right, attack_swing_charge_right_down→attack_swing_charge_right, attack_swing_down_right→attack_push, attack_swing_heavy_right→attack_push, attack_swing_heavy_right_diagonal→attack_push, attack_swing_left→attack_push, attack_swing_up→attack_swing_heavy_right, attack_swing_up_left→attack_swing_left, parry_pose→parry_pose, parry_pose_02→parry_pose` (attack_slam/attack_slam_charge have no Greathammer twin — mapped to nearest)
- **Bardin Coghammer `dr_2h_cog_hammer`** (→ Greathammer, v0.12.151-dev; native owner `dr_ = false`): `attack_push→attack_push, attack_swing_charge→attack_swing_charge, parry_pose→parry_pose` (all pass-through identity — the Coghammer already animates correctly on Kruber's Greathammer SM; baking confirms it and drops the dev toggle)

**Status legend**
- **CONFIRMED** — 3P flawless. Exclude from the picker.
- **`[Needs Animations]`** — anim-SET redirect chosen + working at set level, but the
  per-attack animation mapping still needs the user to pick. Suffix = the chosen set
  (e.g. `[Greathammer]`). Picker shows: `[Needs Animations] <Weapon> [<Set>]` + per-attack dropdowns.
- **`[Needs Offsets]`** — set chosen, 3P grip offset still needed (existing status).

| Weapon (on Kruber) | Likely key | Set chosen | Status | Per-attack picks |
|---|---|---|---|---|
| Bardin's Axe + Shield | `dr_shield_axe` | native-ok | **CONFIRMED** | — |
| Bardin's War Pick | `dr_2h_pick` | **Greathammer** (`es_2h_hammer`) | **BAKED v0.12.149** (`[Working]`) | DONE — `_3p_template_remaps.two_handed_picks_template_1.es_` |
| Bardin's Coghammer | `dr_2h_cog_hammer` | **Greathammer** (`es_2h_hammer`) | **BAKED v0.12.151** (`[Working]`) | DONE — `_3p_template_remaps.two_handed_cog_hammers_template_1.es_` (all-identity) |
| Kerillian's Sword & Dagger | `we_*` (confirm) | redirect chosen — SET TBD (read from redirect table) | `[Needs Animations]` | pending — need that set's anim list once set is confirmed |
| Kerillian's 1H Sword | `we_1h_sword` | native-ok | **CONFIRMED** | — |
| Crowbill | `bw_1h_crowbill` | native-ok | **CONFIRMED** | — |
| Sienna's Dagger | `bw_dagger` | **Empire 1H Sword** (`to_1h_sword`) | **BAKED v0.12.149** (`[Working]`) | DONE — `_3p_template_remaps.one_handed_daggers_template_1.es_` |
| Kerillian's Spear & Shield | `we_spear_shield` (confirm) | native-ok | **CONFIRMED** | — |
| Skullsplitter & Tome | `bw_*` (confirm — Necromancer?) | Kruber 1H Mace (native, NO picks needed) | **MODEL-SUB PORT** | 3P model → swap to the **plain Skullsplitter mesh (HIDE the tome)**; use Kruber's native 1H-mace 3P anims; **1P UNCHANGED**. Pattern = Brace-of-Pistols → Repeater model-sub (model-sub queue, NOT an anim-pick). Queued for the wt impl pass after `wspgmezko`. |
| Warrior Priest's Greathammer ("Reckoner") | `wh_2h_hammer` | **Greathammer** (`es_2h_hammer`) | **BAKED v0.12.151** (`[Working]`) | DONE — `_3p_template_remaps.two_handed_hammer_priest_template.es_` |
| Saltzpyre's Rapier & Pistol | `wh_rapier` (confirm) | Kruber 1H Sword (`es_1h_sword`) | **MODEL-SUB PORT** (then maybe `[Needs Animations]`) | 3P: **HIDE the off-hand pistol unit**; redirect to Kruber's 1H-sword anims; **1P UNCHANGED**. Rapier mesh kept — only the pistol hidden. User: "might need to pick animations" after. Queued after `wspgmezko`. |
| Dual Skullsplitters (Warrior Priest) | `wh_*` dual (confirm) | redirect chosen — SET TBD | `[Needs Animations]` | picker surfaces set + per-attack options |
| Kerillian's 1H Axe | `we_1h_axe` (confirm) | redirect chosen — SET TBD | `[Needs Animations]` | picker surfaces |
| Kerillian Dual Swords | `we_dual_wield_swords` (confirm) | redirect chosen — SET TBD | `[Needs Animations]` | picker surfaces |
| Dual Axes (Bardin) | `dr_dual_wield_axes` | **Empire Mace & Sword** (`to_dual_hammer_sword_es`) | **BAKED v0.12.149** (`[Working]`) | DONE — `_3p_template_remaps.dual_wield_axes_template_1.es_` |
| Sienna's Mace | `bw_1h_mace` | **Greathammer** (`to_2h_hammer`) | **BAKED v0.12.150** (`[Working]`) | DONE — `_3p_template_remaps.one_handed_hammer_wizard_template_1.es_` |
| Sienna's Scythe | `bw_ghost_scythe` | **Greathammer** (`to_2h_hammer`) | **BAKED v0.12.150** (`[Working]`) | DONE — `_3p_template_remaps.staff_scythe.es_` + `[Needs Offsets]` resolved via DURABLE `_weapon_grip_offsets.bw_ghost_scythe.es_ = {0,0,6}` (es_-scoped, 3P-only, per-frame re-apply — v0.12.151 bumped from 0.569 because the one-shot was stomped in-game, see OFFSETS.md) — NOT a `unit_attachment_node_linking` write (that surface is shared with Sienna) |
| Kerillian's Greatsword | `we_2h_sword` (confirm) | native-ok | **CONFIRMED** | — |
| Bardin's Greataxe | `dr_2h_axe` (confirm) | native-ok | **CONFIRMED** | — |
| Kerillian's Glaive (Greataxe/Glaive) | `we_2h_axe` (`two_handed_axes_template_2`) | redirect chosen — SET TBD | `[Needs Animations]` (anim NOT baked — stays in picker). Grip offset SET v0.12.152-dev: DURABLE `_weapon_grip_offsets.we_2h_axe.es_ = {0,0,0.285}` (es_-only, 3P-only, per-frame re-apply — independent of the anim bake; see OFFSETS.md) | picker surfaces |
| Sienna's Flail | `bw_flail` (confirm) | native-ok | **CONFIRMED** | — |
| Warrior Priest's Flail & Shield | `wh_flail_shield` (confirm) | redirect chosen — SET TBD | `[Needs Animations]` | picker surfaces |
| Saltzpyre's Flail (regular) | `wh_flail` (confirm) | native-ok | **CONFIRMED** | — |
| Sienna's Fire Sword | `bw_flame_sword` | **Empire 1H Sword** (`to_1h_sword`) | **BAKED v0.12.149** (`[Working]`) | DONE — `_3p_template_remaps.flaming_sword_template_1.es_` |
| Saltzpyre's Falchion | `wh_1h_falchion` (confirm) | native-ok | **CONFIRMED** | — |
| Kerillian's Volley/Repeater Crossbow | `we_crossbow_repeater` | redirect VALID (`to_repeating_handgun` IS registered + Kruber-native) | **AUDIT: not a redirect crash** | Audit (`wt-redirect-audit`): the elf repeater-crossbow crash was ALREADY FIXED (`weapon_tweaker.lua:2453-2482`); `to_repeating_handgun` is a real registered event (Kruber's native repeating-handgun wield). If Volley still crashes on Kruber it's a DIFFERENT subsystem (skin/projectile/ammo) — need the actual ScriptError. |

> v0.12.149-dev: the 4 finished weapons (Pickaxe, Dual Axes, Sienna's Fire Sword,
> Sienna's Dagger) were BAKED career-scoped into `_3p_template_remaps` and removed from the
> picker (see the BAKED section above). The picker still serves the REMAINING flagged
> weapons (WH 1H Axe, the Kerillian dual/2H ports, etc.); the
> `[wt:apply]`/`[wt:play]` instrumentation is retained to capture future picks.
>
> v0.12.150-dev: + Sienna's Mace + Necromancer Scythe BAKED (Greathammer).
>
> v0.12.151-dev: + **Warrior Priest/Saltzpyre Greathammer (`wh_2h_hammer`)** and
> **Bardin Coghammer (`dr_2h_cog_hammer`)** BAKED (Greathammer) and removed from the picker
> (`_WEAPON_SET` + `_NEEDS_ANIMS` entries deleted; moved to `_CONFIRMED.kruber`). The Scythe
> grip offset was bumped +0.569 → **+6** and moved to the DURABLE per-frame re-apply path
> (the one-shot was stomped in-game — see `OFFSETS.md`). The `wt_passive_charge_restore`
> auto-vent toggle was removed (now implicit/always-on).

## ⛔ BLOCKED — awaiting a usable log

Two ports could not be captured/baked this round because the friend's in-game log has **no
`wt` lines** (mod not active / not logging in his session):

- **Kerillian's Elven Daggers** (`we_dual_wield_daggers` family — confirm exact key) — set
  redirect chosen (Mace & Sword, SET B) but no captured per-attack picks.
- **Kerillian's Elven Axe** (`we_1h_axe`) — set redirect chosen (WH 1H Axe, SET E) but no
  captured per-attack picks.

UNBLOCK by getting a usable log from the friend (with `wt` enabled + `enable_debug_logging`
on, swinging each weapon on Kruber) OR his `user_settings.config` so the picks can be read
directly. Both remain in the picker (`_NEEDS_ANIMS.kruber`) until then.
