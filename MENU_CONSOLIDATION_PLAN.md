# Menu Consolidation Plan

> Shared spec for the **gut menu reorg** + **dev-mod settings consolidation** (2026-06-22).
> Built from a source-verified VMF capability survey + a menu inventory of gut / gt_dev / ct_dev / crt.
>
> **Two agents, one spec.** Section 1 (gut) is the SPEC for the parallel GUI-Tweaker agent (the
> "Advanced Settings button"). Sections 2–4 (gt_dev / ct_dev / crt) are **this** session's work.
> Both build to the VMF recipe in §0. See `STATUS.md` → Coordination.

---

## 0. VMF capability verdict — source-verified, do NOT re-guess

VMF natively supports the **"master toggle → expandable fine-tune submenu"** UX with **zero custom code.**

- **`checkbox` + `sub_widgets`** = master toggle. Children are visible ONLY while the box is checked; unchecking auto-hides the whole subtree and the list re-flows to close the gap. *(`vmf_options_view.lua:4461-4463` — the per-frame visibility loop branches on parent type.)* Persisted values survive being hidden (they live in `mod:get`, independent of widget visibility).
- **`group`** = always-present collapsible container with a user-facing expand/collapse **arrow**; never gates on a checked state *(`vmf_options_view.lua:4477`)*. Seed the initial collapsed state with the mod's `collapsed_widgets = { "id", ... }` list.
- **`dropdown` + per-option `show_widgets`** = reveal a DIFFERENT child subset per selected option *(`:4466-4474`)*.
- Parent-capable types: **header / group / checkbox / dropdown** *(`vmf_options_core.lua:528-533`)*. `numeric` / `keybind` / `text` are always leaves. Nesting depth is unbounded (recursive unfold, `:534-559`).
- **Limits that matter here:** `numeric` slider step is fixed to `10^-decimals_number` (no step field). A checkbox's *displayed* state is cached — `mod:set` from `on_setting_changed` does NOT refresh an already-open widget (so programmatic mutex/dependent-checkbox patterns fail visually). Note: auto-hide-on-uncheck does **not** suffer this, because it's value-driven every frame.

### Canonical recipe (copy this)

```lua
{ setting_id = "feature_master", type = "checkbox", default_value = false,
  sub_widgets = {
    { setting_id = "feature_strength", type = "numeric",  range = {0,10}, decimals_number = 1, default_value = 1 },
    { setting_id = "feature_mode",     type = "dropdown", default_value = "a",
      options = {{text="opt_a",value="a"},{text="opt_b",value="b"}} },
    { setting_id = "feature_extra",    type = "checkbox", default_value = false },
  },
}
```

### The routing rule — which tool per cluster

| Case | Tool | Why |
|---|---|---|
| Master on/off + a few fine-tune values | **`checkbox` + `sub_widgets`** (native) | Free; auto-hides the values when off. gut already uses it. |
| Always-present bundle of independent settings | **`group`** (native, collapsible) | User expands when needed; no master gate. The repo's existing standard. |
| One setting with **numerous** values / rich custom controls | **gut "Advanced Settings" button/popup** | Native inline expansion would flood the scrolling list; a popup keeps the main menu clean and allows controls VMF's widget set can't draw. ← the parallel gut agent's deliverable. |

> **Key implication:** the dev-mod consolidation (§2–4) is **NOT blocked** on the gut button. The light + bundle cases are native VMF and can start as soon as the WIP lands. Only genuine "numerous values" cases wait for the button.

---

## 1. gut (GUI Tweaker) — reorg spec  *(for the parallel gut agent)*

**State:** 52 widgets, 8 flat top-level entries, no umbrella, **two confusingly-similar hide-UI surfaces** as siblings. Color-picker fine-tunes already use the native master-toggle pattern (good model).

**Target top level (3 buckets, self-documenting, provenance jargon renamed):**

1. **Hide HUD & UI** *(collapsible `group` — THE primary win)*
   Fold the two duplicate visibility surfaces into one: `gut_hud_visibility_group` ("Hide UI" 3-mode dropdown + cycle hotkey) **and** `hb_group` ("UI Tweaks (absorbed)"). Inside: (a) HUD-mode dropdown + cycle hotkey at top, (b) `HIDE_UI_ELEMENTS_GROUP` sub-group, (c) `HIDE_BUFFS_GROUP` sub-group. Move the 3 loose `hb_group` toggles (`force_default_frame`, `UNOBTRUSIVE_FLOATING_OBJECTIVE`, `UNOBTRUSIVE_MISSION_TOOLTIP`) into a sub-group. Rename "UI Tweaks (absorbed)" → "Hide UI Elements & Buffs". *Pattern: collapsible_group (the per-element checkboxes are independent opt-ins, not all gated by one boolean).*
2. **On-Screen Overlays** *(optional umbrella; already-correct `master_toggle_plus_finetune`)*
   `gut_parry_indicator` → R/G/B; `gut_respawn_timer` → font size + R/G/B. No change needed; can optionally sit under one umbrella for symmetry.
3. **Advanced** *(collapsible `group`)*
   `gut_compat_group`/`gut_buffbar_endtime_fix` + `gut_config_override`. **`enable_debug_logging` stays loose & LAST** (PROJECT_STANDARDS convention) — do not fold it in if that would move it off last position.

---

## 2. gt_dev — umbrella catalog  *(this session)*

**State:** 155 widgets, group-based but accretion-ordered (not A→Z); bots split across 3 groups; noclip fine-tunes loose. Several clusters already use native `sub_widgets` master-toggles (good).

| Umbrella | Master / pattern | Folds in |
|---|---|---|
| **Improved Bot Behavior** ← user's canonical example | `gt_bot_behavior_improvements` as **expandable master** (`master_toggle_plus_finetune`) | `gt_improved_bot_combat`, `gt_bot_rescue_awaiting`, `gt_bot_split_among_players`, `gt_bot_follow_host`, … (currently flat siblings) |
| **Bot Population / Party Composition** | relocate into `gt_bot_options_group` | `gt_bots_in_keep`, `gt_no_bots`, `gt_bot_toggle_hotkey`, `ult_bot_cap_enabled`, … |
| **Noclip** | `noclip_enabled` expandable master | `noclip_speed`, `noclip_boost_multiplier`, `noclip_hotkey` |
| **Third-Person Camera** | `tp_camera_enabled` expandable master | `tp_distance`, `tp_height`, `tp_side_offset`, `tp_disable_zoom_in` |
| **Cutscenes & Loading** | extend `gt_cutscenes_group` | `gt_solo_disable_intro_audio`, `_fog`, `_sun_shadows`, `_mutator_explosions` |
| **Host-Side Lobby Controls** | master gates per sub-feature | `gt_lobby_*` (kick-idle, MOTD, slot reservation) |
| **Godmode & Survival** | light grouping (don't over-merge) | `godmode_enabled`, `disable_friendly_fire`, `gt_fall_damage_enabled`→`gt_fall_damage_mult` |

Plus: A→Z the top-level group order.

---

## 3. ct_dev — umbrella catalog  *(this session)*

**State:** 130 widgets, well-grouped at the leaf level but **almost no master toggles** — exactly the user's pain ("I want one switch to enable a whole subsystem instead of hand-ticking many boxes").

| Umbrella | Pattern | Folds in |
|---|---|---|
| **Altar Reuse** | `enable_altar_reuse` master | the `altar_reuse_*` count/cost_mult cluster (8) |
| **Curse Control** | `disable_all_listed_curses` master | `disable_curse_*` (14) — *but keep per-curse boxes reachable; consider collapsible so master-off doesn't hide them* |
| **Boss Grudge Marks** | `ban_all_grudge_marks` master | `ban_grudge_mark_*` (13) |
| **Banned Weapon Traits** | `ban_all_traits` master over both subgroups | `ban_trait_vanilla_group` (15) + `ban_trait_chaos_wastes_group` (19) — `collapsible_group` |
| **Disabled / Starting Boons** | keep collapsible + add per-category "disable whole category" convenience | `disable_boon_*` / `start_boon_*` (~140 each, BOON_TREE) |
| **Boon Reworks** | `enable_boon_reworks` master | `enable_boon_vauls_anvil`, `_manann_tempest`, `_taal_twinned_arrow`, `_asuryan_wrath` |
| **Adventure Maps** | confirm `inject_adventure_maps` master gating is surfaced (it already gates `inject_pool()`) | `replace_shrines_with_missions`, `available_missions_group` |

Plus: A→Z the top-level group order. (Bomb-Boon + Bot-Boon-Behavior soft sub-umbrellas inside Reworks.)

---

## 4. crt — umbrella catalog  *(this session)*

**State:** 118 live widgets, well-grouped by character but per-cluster masters missing. The Big Rebalance `cbr_*` cluster (~160) is commented out / inert — **leave it**.

| Umbrella | Pattern | Folds in |
|---|---|---|
| **Sienna Unchained Rework** | master | `rework_bw_unchained_*` (9) |
| **Outcast Engineer Rework** | master | `rework_dr_engineer_*` (4, incl. Leading Shots) |
| **Armor (Gromril & Cursed Armor)** | master | `armor_gromril_ignore_chip`, `armor_specials_dont_break_gromril` |
| **Per-career Rework masters** | collapsible per career inside Talent Reworks | `rework_dr_ranger_group`, `rework_dr_slayer_group`, `rework_es_huntsman_group`, `rework_es_mercenary_group`, … |
| **Tourney Balance** | whole-group master | `trn_*` (17 across 5 character subgroups) |

Note: `talent_reworks` and `trn` use roster order (deliberate, A→Z-exempt) but are **inconsistent with each other** — unify on one roster order during the pass.

---

## Sequencing

1. **Land the 5-day WIP first** (clean tree — STATUS.md).
2. **One mod in flight** at a time (STATUS.md rule 1). Suggested order: gut (gut agent, in parallel) → gt_dev (the bot-behavior exemplar) → crt → ct_dev (biggest).
3. Each pass also does the **A→Z top-level reorder** (repo standing rule) and adds `[untested]` labels to any new/changed menu entry.
4. Heavy "numerous values" cases get routed to the gut Advanced Settings button once its registration contract exists.
