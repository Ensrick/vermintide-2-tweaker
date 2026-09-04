# Tweaker: GUI — Changelog

## 0.2.289 (2026-09-03) — owner-aware Mod Tweaker slider steps (#389)

### Why

- Official v0.2.288 retained the 25-point Base Power Level contract, but both
  Mod Tweaker presentation paths looked it up through the synthetic
  `gut_equipment` category instead of the setting's CIM owner. Per-node
  Equipment ownership (#208) and step policy (#164) each worked in isolation,
  but their merged configuration seam was not exercised. The detached resolver
  check therefore passed while the live row fell back to one-point steps.

### Changed

- Resolves numeric steps through the setting-qualified owner in the active
  standalone view and the dormant Keep hero-view implementation. Normal
  categories, explicit widget steps, and natural decimal increments keep their
  existing precedence and behavior.
- Restores the shared stable registry's `ct`/`ct_dev` Trial Chest Cost entries,
  retaining the closed #826 consumer as a control alongside Starting Coins.
- Adds `issue389_mod_tweaker_owner_aware_step` to `/gut_regression_test`. It
  drives the real Equipment synthesizer, the active standalone row builder,
  real owner-qualified staging, and the installed typed-edit and arrow
  callbacks with a non-mutating local sink. It proves the arrow release latch,
  rejects a missing owner, and retains normal-category and explicit-step
  controls. When the dormant Keep twin is loaded, the check builds its real row
  and drives its installed arrow handler; offline QA also drives the installed
  state drag handler with an off-grid value.
- Emits at most one `[gut:issue389]` receipt per presentation and game process
  when the real Base Power Level row is built, recording route, category,
  resolved owner, and step without requiring mod logging.

### Verification

- In Equipment > Crafting, Base Power Level must move in 25-point increments
  with arrows, track clicks, and drag commits on the official standalone Mod
  Tweaker route. Reopening the menu must retain the selected value.
- Click the Base Power number, type `324`, and commit with Enter (then repeat by
  clicking away): it must stage `325`. Pressing Escape during another edit must
  cancel without moving or saving the value. Crafting afterward must use the
  selected power; `950` is the authored maximum, so an entered `1000` tests only
  clamping to `950`.
- Starting Coins, Trial Chest Cost (when CT Dev is present), and an unrelated
  numeric setting remain controls, and `/verify_gut_slider_step` and
  `/gut_regression_test` must pass
  `issue389_mod_tweaker_owner_aware_step`.
- The session log must contain one standalone receipt with
  `category=gut_equipment owner=cim` (or `cim_dev`) and `step=25`.

### Notes

- This is a selective stable promotion of the narrow owner-aware resolver from
  GUI Dev. It excludes every unrelated GUI Dev feature.
- `_USE_KEEP_SUBSTATE = false` keeps the HeroView substate dormant. The ESC
  button, hotkey, and canonical `/mod_tweaker` command all use the standalone
  view. The dormant implementation remains source-covered so its owner lookup
  and min-anchored typed/arrow/drag grid cannot regress if it is re-enabled.

## 0.2.288 (2026-08-30) — verified Damage Taken award promotion (#1151)

### Why

- Promote the independently verified end-score correction without absorbing
  unrelated GUI Dev work.

### Changed

- Recomputes only the Damage Taken row's green-circle candidate from the
  numeric scores vanilla already accumulated, so the lowest positive value can
  win while legitimate zeroes and ties remain valid (#1151).
- Leaves every other scoreboard row, renderer, transport, and persistence path
  unchanged. Diagnostic evidence remains bounded to eight records per process.

### Verification

- Rain verified the corrected winner in an Adventure end screen on GUI Dev and
  the attached session log recorded the bounded repair plus a passing
  `issue1151_damage_taken_green_circle_minimum` runtime check.
- The promoted adapter and pure policy are the byte-proven GUI Dev implementation,
  changed only for the stable `gut` namespace and source path.

### Notes

- This is a selective stable promotion. It excludes every open, diagnostic, and
  otherwise unverified GUI Dev feature.

## 0.2.287 (2026-08-29) — verified WT Dev discovery and clean labels (#636, #694)

### Why

- Promote only the two independently verified Mod Tweaker compatibility fixes
  that remain absent from the stable stream.

### Changed

- Recognizes both `wt` and `wt_dev` as Tweaker: Weapons registration aliases
  and folds the enabled stream into one Equipment > Weapons collapsible in the
  Keep and mission presentations. Weapon Availability, the Development
  Animation Picker, and the Development Weapon Hold-Pose Tuner remain owned by
  WT Dev and visible beneath that section (#636).
- Removes legacy engineering lifecycle decorations such as `[Working]`,
  `[Untested]`, `[Issue N]`, and `[verify-fix]` at the Mod Tweaker label-resolution
  boundary while preserving functional qualifiers such as `(CWV)`, `[Host Only]`,
  `[Client]`, `[WARNING]`, `[EXP]`, and units (#694).
- Centralizes authored-mod discovery and Equipment stream aliases so the two
  presentation paths cannot drift independently.

### Verification

- With Tweaker: Weapons Dev and CWV enabled and public WT disabled or absent,
  inspect Equipment > Weapons in the Keep and in a mission, then run
  `/gut_regression_test`; `issue636_wt_dev_equipment_collapsible` must pass.
- Inspect tab, collapsible, setting, and option labels across installed Tweaker
  mods. Engineering lifecycle decorations must be absent and functional
  qualifiers must remain unchanged.

### Notes

- This is a selective stable promotion. It does not import unrelated GUI Dev
  work, change the public Workshop identity, or alter Mod Tweaker row-color
  policy.
- Normalizes away the SDK tool-only LUT-generator sidecar so clean rebuilds and
  reviewed publication receipts describe the same runtime artifact set.
- VT2-Bundle-Retirement: `e7852992f40eb619.mod_bundle`

## 0.2.286 (2026-08-28) — verified DEFAULT transaction promotion (#312, #446, #631, #649, #1002)

### Why

- Publish the verified 0.2.285 selective GUI set together with the independently
  verified Equipment DEFAULT transaction correction, without absorbing any
  other development-line work.

### Changed

- Carries forward the reviewed #312, #446, #631, and #649 stable changes
  unchanged.
- Treats silent-write and owner batch-callback failures as incomplete
  transactions, retains only the incomplete owner's pending buffer, defers
  profile capture and switching until retry succeeds, and re-registers keybinds
  only after a complete commit (#1002).
- Reconciles the stable Workshop identity `3732144878` with its intended public
  visibility in both `itemV2.cfg` and the canonical mod inventory.

### Notes

- Excludes #272 and every other unverified or dev-only change. The three stable
  scoreboard modules remain byte-identical to the reviewed 0.2.285 baseline.

## 0.2.285 (2026-08-26) — verified selective stable promotion (#312, #446, #631, #649)

### Why

- Promote only the GUI changes that have explicit user or tester verification,
  while keeping unverified development work out of the non-dev Workshop item.

### Changed

- Promotes mouse buttons 1–5 as Mod Tweaker keybind primaries, including
  release-committed mouse capture so the click that begins capture cannot bind
  or clear itself (#631).
- Adds native-style mutually exclusive radio controls and folds the live UI
  Tweaks settings tree into Mod Tweaker while preserving the owning mod's live
  values, ordering, and profile boundary (#446, #312).
- Guards mission-completion statistics against late or custom careers whose
  statistics rows are absent, without changing valid native results (#649).

### Notes

- Withholds the unverified 0.2.283/0.2.284 scoreboard candidate from the
  Workshop artifact. Stable scoreboard code remains byte-identical to the last
  live 0.2.281 presenter; the candidate and its history remain preserved in Git.

## 0.2.284 (2026-08-25) -- stable scoreboard release reconciliation (#272) [not-started]

- Reissues the reviewed 0.2.283 stable scoreboard correction under the fresh
  version reservation required after its original ship claim expired before
  Workshop publication. The explicit-root 11-by-4 renderer, enabled-aware
  external-scoreboard handoff, and zero-custom-transport boundary are unchanged.
- This is an artifact/provenance reconciliation only. Paging, visibility, and
  host-authoritative custom statistics remain owned by #272 and #1414.

## 0.2.283 (2026-08-23) -- stable scoreboard presentation parity (#272) [not-started]

- Replaces the public stream's flattened multiline scoreboard overlay with the
  reviewed explicit-root, fixed-cell 11-statistic by 4-player grid already used
  by GUI Tweaker Dev. Hold Tab and the Adventure end screen still consume the
  same detached native snapshot.
- Adds the missing title/header localization and makes a loaded but disabled
  standalone Tab Scoreboard yield the surface to GUI Tweaker. An enabled or
  unreadable external scoreboard remains the sole owner to avoid double draw.
- Adds a semantic stable/dev parity assertion, preserving the existing bounded
  four-Hz refresh, eight-receipt evidence cap, and zero custom-stat transport.
  This repairs the public regression but does not complete #272's paging,
  visibility, or host-authoritative custom-stat phases.

## 0.2.281 (2026-07-22) -- detached bot loadout snapshots (#954) [not-started]

- Assigning a saved loadout to a bot now persists a dedicated copy of that
  row's equipment. Later edits to the player's saved row no longer mutate the
  bot's live or persisted equipment through the same table identity.
- Existing bot designations migrate once from their current designated row.
  Every backend refresh receives another detached copy, so backend cache writes
  cannot alias the persistent snapshot. Official-realm behavior remains native.
- Added stable/dev Lua truth-table, deep-copy, runtime-wiring, and live
  `/gut_regression_test` coverage.

## 0.2.280 (2026-07-19) — reconcile newly added settings into existing profiles (#828) [verify-fix-coop]

- Upgrades sparse saved profiles from the current declared defaults while preserving every explicit saved value, including `false` and explicit opt-ins.
- Applies only missing members through the existing bounded owner transaction and persists the upgraded snapshot only after every addition succeeds.
- Keeps stable/dev and standalone/keep-state profile behavior aligned, with bounded `[gut:828]` receipts only when a migration is actually needed.

## 0.2.278 (2026-07-17) — GUI hard-limit recovery

- Extracted the standalone and HeroView Mod Tweaker input/draw surfaces behind explicit install APIs, without changing their interaction behavior or hook ownership.
- Extracted Mod Tweaker runtime contracts and the absorbed UI Tweaks integration from the main entry point while preserving stable/dev parity and intentional dev-only Dialogue behavior.
- Added offline contracts for single module ownership, duplicate class methods, lifecycle neutrality, dependency parity, and root-package coverage.

## 0.2.277 (2026-07-17) — #611 advanced-option master presentation

- Gear/advanced-option parent rows now use the established warm-tan menu accent, clearly separating bulk/master controls from their individual child settings.
- Disabled gear parents remain grey, and the rule applies consistently to every advanced-options parent rather than hard-coding one mod's setting IDs.

## 0.2.276 (2026-07-15) — #522 inventory preview lighting correction [untested]

- Retired the nonfunctional alternate-level backdrop swap. Inventory keeps the exact vanilla preview package, level, geometry, camera, and background.
- Replaced the old choices with Vanilla, Dim (65% exposure), and Dark (40% exposure). Legacy Dark Camp and Victory Camp values migrate deterministically to Dim and Dark.
- The selected exposure is applied only through the live `HeroWindowCharacterPreview` preview world's post-blend shading callback. Any prior callback is chained and restored exactly on Vanilla, window close, or mod disable; the hot path allocates nothing.
- Added source-backed regression coverage for preview-world scoping, in-place setting changes, legacy migration, and exact callback restoration.

## 0.2.275 (2026-07-15) — public rollup of dev 0.2.121-dev..0.2.275-dev

### Why

Promotes the release-ready Tweaker: GUI development line into the stable mod while keeping experimental commands, automatic issue probes, and research-only modules out of the public bundle.

### Changed

- Mod Tweaker now has search with transient collapsible state, per-tab profiles, bounded batch Apply/Default transactions, corrected numeric caret geometry, exact compact tab labels, disabled-mod sections in place, tree-preserving group ordering, and the native search icon (#318, #497, #525, #557, #559, #560, #561, #572, #575).
- Vanilla Options remains entirely stock for Crosshair Kill Confirmation: no injected gear icon, checkbox conversion, suppression, redirect, or OptionsView hook survives the promotion (#528).
- Added native-style Mod Tweaker action rows and lazy providers used by Character Dialogue without eagerly allocating its generated catalogue (#605).
- Promoted modded-realm native loadouts, cosmetic/CWV overlay isolation, live slot-capability validation, and crash-safe unresolved-item fallbacks (#175, #287, #353, #372, #379, #387, #402, #539, #619).
- Promoted optional in-mission inventory, hero selection, customization, crafting access, and mission selection with resource-residency guards (#80, #87, #155, #172, #193, #305, #336, #363, #530, #539).
- Promoted third-person camera, free camera, floating damage numbers, startup/menu options, loading-monologue control, and wired-only cutscene skipping. Locked boss cinematics remain untouched and post-skip fades/cameras cannot re-arm (#106, #140, #190, #191, #192, #202, #209, #216, #275, #307, #537).
- Promoted HUD editing/hiding, corrected drag geometry, UI Tweaks compatibility, bot victory-pose repair, held-Tab weapon/talent refresh, native scoreboard improvements, disconnect retention, and On Yer Feet revive attribution (#232, #245, #250, #272, #281, #310, #312, #437, #438, #547).
- Promoted Armory/Bestiary HeroView integration, inventory backdrop selection, original temporary-health names, source-confirmed hidden passive descriptions, and Simple UI confinement (#153, #217, #223, #224, #314, #352, #522).
- Stable localization strips every dev lifecycle/status tag. The stable package now explicitly includes the absorbed `hb/` Lua subtree.

### Public exclusions

- Excluded the experimental `/gut_swap_career` feasibility command.
- Excluded every normal-Options extension, including the still-unverified Video Profiles feature (#292), plus the Options layout probe, loadout-capacity census, Well of Dreams trace, WT loadout trace, all-language detect-only scaffold, career-HUD-holder census, and central scoreboard diagnostics.
- Removed the 30-second frame-time and launch-memory probes; routine cutscene telemetry is VMF-debug-gated rather than always-on.

### Notes

- Public Workshop identity and configured visibility are preserved exactly (`published_id = 3732144878`, `friends_only`).
- This is an independent stable source tree; no runtime dependency on `gui_tweaker_dev` remains.

## 0.2.120 (2026-07-13) — Fixed 25-point weapon-power steps (#389)

- Promoted Mod Tweaker's foreign-slider registry to stable. CIM's Base Power Level and CT's Starting Coins use fixed 25-point increments for both registered stable/dev mod ids.
- Mirrored the registry into both UI presentations; explicit authored steps still win and ordinary numeric settings keep their natural increment.

## 0.2.119 (2026-07-13) — Tree-preserving Mod Tweaker layout (#557) [not deployed]

- Every unordered sibling level now displays collapsible groups first and loose settings second; both partitions sort case-insensitively by localized display label.
- Sorting reconstructs the depth tree and emits whole subtrees, so a group never separates from its descendants. Authored headers and explicit order/dependency metadata preserve their sibling sequence.
- The deliberately synthesized Equipment layout opts out completely. Both the standalone and keep-sub-state presentations use the same pure ordering policy, with offline recursive/subtree regression coverage.

## 0.2.118 (2026-06-30) — Removed the absorbed "UI Tweaks (absorbed)" HideBuffs Phase-1 feature set (hide-UI-elements + hide-active-buffs groups, Hide-HUD hotkey, loading-screen hides) from the public alpha; it remains in gut_dev. Compatibility shims (buff-bar end-time crash fix, baked-in Temporal Fix) and the native "Hide UI (3 modes)" feature are unaffected. (#94)

## 0.2.117 (2026-06-28) — Removed per-mod debug toggle; diagnostics now route through VMF logging (mod:debug / mod:warning), gated by VMF output_mode_debug / output_mode_warning. (#169)

## 0.2.116 (2026-06-28) — promoted gut_dev confirmed-working state

Promoted the confirmed in-game working state of `gui_tweaker_dev` (gut_dev v0.2.116-dev) to stable.

**Mod Tweaker UI fixes (live-keybind capture, tabs-in-submenu, widget rendering):**
- Live keybind capture in Mod Tweaker settings rows — keybind values now show the human-readable combo ("LEFT ALT", "CTRL + F") or "unbound" instead of a raw table address (#95).
- Tabs-in-submenu support for nested settings groups.
- Slider arrow/drag fixes: stepper/slider arrows draw at native sprite size (30×35); the drag thumb uses a grab-offset anchor instead of absolute-position snap that caused the thumb to jump (#91, #92).
- Dropdown up-arrow + glow fix: the collapsed dropdown now shows both a down-arrow (closed state) and up-arrow (open state) correctly, with the `drop_down_menu_arrow_clicked` glow sprite layering on hover (#92).
- Dropdown click/hover bleed fix: click and hover events no longer bleed across adjacent rows.
- Declared-step support for numeric/slider widgets.

**In-mission inventory + hero-select (#87, migrated from general_tweaker 2026-06-24):**
- Opens the keep inventory (Equipment/Talents/Cosmetics tabs) mid-mission via `/gut_inv` or the keybind — adventure only, blocked in Chaos Wastes.
- Opens the Talents layout mid-mission via `/gut_hero_select` or keybind — talent/ability changes apply to the live character immediately (#87).
- Crafting/Forge tab gated OFF mid-mission unless Crafting in Modded (cim/cim_dev) is loaded — opening it without cim crashes (keep-only preview level).
- Cosmetics tab disabled mid-mission (gui_pose_items_atlas not resident mid-mission → C-fatal; #155).

**Skip Cutscenes (migrated from general_tweaker 2026-06-25, #106):**
- Allow cutscenes to be skipped with ESC or Space; optional auto-skip mode; CW boss/phase cinematics are left alone to avoid fight desync.
- Printf-based `[gut:cutscene]` diagnostic survives mod-logging-off (#106 stuck dlc_castle cutscene instrument).

**UI Tweaks / HideBuffs re-enabled (hb/ dir restored):**
- Hide UI elements, hide active buffs, loading-screen hides, Hide-HUD hotkey (the Phase-1 HideBuffs-fork port that was temporarily stripped in 0.2.85-alpha is now confirmed stable and re-included).

**Dual-version (cim/cim_dev) dependency detection:**
- `_gut_mission_inventory.lua` now uses `_has_cim()` (returns `get_mod("cim") or get_mod("cim_dev")`) so the in-mission inventory/customize menus appear whether the user runs the stable or dev sibling of Crafting in Modded.

## 0.2.85-alpha (2026-06-24) — stripped absorbed UI Tweaks/HideBuffs from public alpha

Removed the absorbed **UI Tweaks (HideBuffs)** hide-elements / hide-buffs feature set from the
PUBLIC alpha. It is **kept on gut_dev** (`gui_tweaker_dev`) for continued development and will be
promoted back here only once verified.

- **Removed** the `hb/` subdir (`hb_data.lua`, `hide_elements.lua`, `level_loading_screen.lua`,
  `mod_events.lua`) and its three `mod:dofile` loads from `gui_tweaker.lua` (the Phase-1
  "hide UI elements / hide active buffs / loading-screen hides / Hide-HUD hotkey" port).
- **Removed** the `hb_group` widget group (and its `HIDE_UI_ELEMENTS_GROUP` / `HIDE_BUFFS_GROUP`
  sub-groups) from `gui_tweaker_data.lua`, plus all the matching loc keys from
  `gui_tweaker_localization.lua`.
- **Removed** the `scripts/mods/gui_tweaker/hb/*` glob from `gui_tweaker.package`.
- **Description recut** (`itemV2.cfg` + `mod_description` loc): dropped the
  "HideBuffs-style HUD-element hiding" feature bullet. The Mod Tweaker menu + HUD customization
  bullets are unchanged.
- **Kept** (NOT part of this feature): the **Mod Tweaker** settings menu, the **HUD customization**
  + gut **hide-HUD mode** (`_hide_ui` / `gut_hud_*` — its own core feature, migrated from
  general_tweaker, unrelated to HideBuffs), and the `gut_compat_group` "UI Mod Compatibility"
  patches (UI Tweaks temporal fix, buff-bar end-time fix, parry indicator, respawn timer,
  NumericUI cooldown, LA atlas keep-alive). The temporal/buff-bar patches operate on the user's
  SEPARATELY-installed standalone HideBuffs mod via `get_mod("HideBuffs")` and are independent of
  the stripped `hb/` fork.

## 0.2.84-alpha (2026-06-24) — FIRST PUBLIC release: Mod Tweaker UI fixes + visibility → public

gut's first `visibility = "public"` Workshop release. The four Mod Tweaker UI fixes from
gut_dev v0.2.85-dev are applied here too (same logic, respecting the `gut` mod id).

**#95 — keybind/non-scalar value showed a raw table address.** Read-only Mod Tweaker rows
(keybind / text / unknown) did `tostring(val)`; a keybind's value is the VMF key-combo ARRAY,
so it printed "CYCLE HUD MODE: table: 0x...". New `_format_keybind_value` helper renders the
combo ("LEFT ALT", "CTRL + F") or "unbound" for `{}`, and the read-only branch routes any
table value through it.

**#91 — scrollbar thumb couldn't be dragged (jumped to top).** Replaced the absolute
cursor→scroll map with a grab-offset drag (anchor scroll_value + cursor Y on first held frame,
track the cursor delta over the thumb's real travel). The grabbed point stays under the cursor.

**#92 — inc/dec + dropdown arrows had no hover highlight.** Restored a native-style hover GLOW
(a larger `settings_arrow_clicked` / `drop_down_menu_arrow_clicked` drawn over the always-present
idle arrow, gated on that arrow's hotspot hover — a glow overlay, not a base-texture swap).

**#93 — Compact ESC menu is now always-on implicit.** Removed the `gut_compact_esc_menu` toggle
+ setting + loc keys; the `HeroWindowIngameView._update_presentation` hook always runs (no-op
below the overflow threshold).

**Visibility → public.** `itemV2.cfg` `visibility` flipped `friends_only` → `public`. Uploaded
with `--allow-public`. Description (the accurate "(alpha)" 3-feature list), Chaos-warrior preview
(`tweaker_gui.jpg`), and Buy-Me-a-Coffee button are unchanged.

## 0.2.83-alpha (2026-06-24) — public-alpha whittle: save-loadouts pulled (untested)

Start of the public-alpha trim. The **Loadout Save/Restore** feature (the
`/gut_save_loadout`, `/gut_load_loadout`, `/gut_list_loadouts` commands — a
reimplementation of loadout_manager_vt2) was **removed from the public alpha** because
it's untested/incomplete. The full feature **stays in `gui_tweaker_dev` (gut_dev)** for
continued development and will be promoted back here only once verified.

- **Removed** the ~325-line Loadout Save/Restore block from `gui_tweaker.lua` (the three
  commands + their `_snapshot_loadout` / `_apply_loadout` / `_validate_item_for_slot` /
  career helpers + the `loadouts` persisted store). It was fully self-contained — no
  hooks, no VMF data widgets, no dedicated loc keys — so the removal does not touch any
  other gut feature (Mod Tweaker settings view, HUD customization/visibility, HideBuffs
  hiding, parry/respawn indicators, etc. all stay).
- **Updated** the boot "ready" log line and the VMF `mod_description` to drop the
  loadout claim.
- **Rewrote** the Workshop `itemV2.cfg` description to accurately list what the alpha
  actually ships (Mod Tweaker settings menu, HUD customization/visibility, HideBuffs-style
  HUD-element hiding). Kept the bug-report block + Buy-Me-a-Coffee button + preview.

Public alpha only — `gui_tweaker_dev` (gut_dev) was NOT touched; save-loadouts remains
fully present there.

## 0.2.82-dev (2026-06-24) — Mod Tweaker polish: native menu sounds, no pressed-on-hover arrows, top-section padding

Five Mod Tweaker chrome fixes to bring the custom settings view closer to the real
vanilla options menu. Both presentations (the standalone in-mission `ModTweakerView`
and the keep-path `HeroViewStateModTweaker` sub-state) were updated in lockstep.

**ITEM 1 — menu ENTER + EXIT sounds (root-cause fix).** The standalone view's
on-enter `Play_hud_button_open` was inaudible, and there was no close sound at all.
Root cause: the wwise-world resolver did `World.wwise_world(Managers.world:world(
"music_world"))`, which is WRONG on PC. On Windows `GLOBAL_MUSIC_WORLD = true`
(boot_init.lua:23), so the music world is NOT registered with `Managers.world` — it
lives as the boot globals `MUSIC_WORLD` / `MUSIC_WWISE_WORLD` (boot_init.lua:31-33).
The lookup returned nil and EVERY `WwiseWorld.trigger_event` no-op'd (so click + hover
were silent too). `_wwise_world()` now resolves exactly as vanilla `OptionsView` does
(options_view.lua:282-288): prefer `MUSIC_WWISE_WORLD` when `GLOBAL_MUSIC_WORLD` is set,
else fall back to `Managers.world:wwise_world(world)`. Added a `_play_close()` wired into
the standalone view's single `exit()` funnel (covers ESC / X / return-to-game), playing
`Play_hud_button_close` (options_view.lua:1691/:2594). The keep sub-state's `close_menu`
sound was switched from `Play_gui_achivements_menu_close` to the same
`Play_hud_button_close` for parity; its enter sound already routes through the parent
hero_view's reliable `play_sound`.

**ITEM 2 — checkbox/toggle click sound.** Was already calling `_play_click()`
(`Play_hud_select`, options_view.lua:544) on toggle in both twins — silent only because
of ITEM 1's broken wwise-world resolution. The ITEM 1 fix makes it audible.

**ITEM 3 — tab hover sound.** Was already calling `_play_hover()` (`Play_hud_hover`,
options_view.lua:423) on the tab hover-enter edge in both twins — same story: audible
once ITEM 1 is fixed.

**ITEM 4 — no pressed-down image on hover (arrows + dropdown arrows).** The slider/
stepper inc/dec arrows hard-swapped their base texture `settings_arrow_normal` ->
`settings_arrow_clicked` on hover, and the dropdown arrow swapped `drop_down_menu_arrow`
-> `drop_down_menu_arrow_clicked` on hover. Both read as a pressed-down button under the
cursor. Vanilla never hard-swaps these on mere hover — it fades a soft glow overlay's
ALPHA (on_stepper_arrow_hover, options_view.lua:4335-4351) and otherwise relies on the
row highlight. Removed the inc/dec arrow swap from `_apply_row_hover` (arrows stay on
`settings_arrow_normal` always) and removed the dropdown's `arrow_down_hover` pass +
style + `arrow_hover_tex` content. Hover feedback now comes solely from the whole-row
`playerlist_hover` highlight (unchanged — the user confirmed it looks right). The gear
drill cog's brightness swap is untouched (it's a highlight, not a pressed look).

**ITEM 5 — padding between top-level collapsible sections.** Top-level (depth-0)
`group` headers stacked flush. A `TOP_SECTION_GAP` (14px) is now decremented off the
running list offset just before each depth-0 group header — except before the first row
(no dead band at the top). Child rows inside a section (depth > 0) are untouched, so
intra-section spacing stays tight like native. The gap is included in `_content_h`, so
scroll bounds and the scrollbar thumb fraction stay correct.

## 0.2.81-dev (2026-06-24) — LA atlas keepalive: stop the per-open "not resident, skipping pin" spam

With `enable_debug_logging` ON, every keep entry and every Mod Tweaker open logged
`[gut] LA atlas package not resident at on_enter; skipping pin this entry` — repeated
endlessly for any user who has Loremaster's Armoury installed but whose LA atlas package
isn't resident at pin time (LA dynamically unloads its own package, so the not-resident
state is common). The log line was already gated behind `enable_debug_logging`, but when
that toggle is on the identical line drowned out every other debug message.

**Cause.** `_pin_la_package` is invoked from FOUR sites — `StateInGameRunning.on_enter`
plus the three Mod Tweaker open re-pins (`gui_tweaker.lua`, `_mod_tweaker_view.lua`,
`_mod_tweaker_state.lua`) — and each re-checked residency and re-logged the not-resident
result every time. Nothing cached the last-observed state, so the same "skipping" line
fired on every entry/open with no new information.

**Fix — edge-triggered logging.** A new file-local `_logged_not_resident` latch makes the
"not resident, skipping pin" line fire only on the TRANSITION into not-resident (the first
call that sees it not resident since it was last resident), not on every call. The latch is
cleared the moment LA's package becomes resident again, so a genuine later unload still
surfaces exactly once. Worst case is now one line per residency transition instead of one
per menu open.

**Guard preserved.** The crash-class guard from v0.2.54 is untouched: we still ONLY pin via
`pm:has_loaded` + `pm:load` ref-count bump when LA's package is already resident, and NEVER
force-load a non-resident LA package (that path C-fatals outside pcall —
`reference_vt2_la_package_force_load_crash`). When LA is present and its package is resident,
the pin still succeeds and keeps the atlas alive across LA's own unloads; when LA is absent
the keepalive no-ops before reaching any log. The per-open `[gut:la] mod-tweaker open #N`
instrumentation (one line per open, carries the open counter) is intentionally left in place.

## 0.2.80-dev (2026-06-23) — Mod Tweaker: bottom scroll padding so near-bottom dropdowns fit

A per-attack anim dropdown opened on a row near the BOTTOM of the Mod Tweaker list (e.g.
Sienna's Mace in the wt anim picker) dropped its options past the bottom edge of the menu,
and the list wouldn't scroll any further to bring them into view — so the lower options
were unreachable.

**Cause.** The dropdown popup (`create_dropdown_list`) anchors one row-height below its
collapsed row and descends DOWNWARD; it's drawn outside the row-cull loop so it isn't
clipped to `list_mask` and can extend past the visible list. But the scroll range topped
out at the last real row (`content_h = row-stack height + 20`), so a near-bottom row had
no headroom to be scrolled UP — its open popup hung off the bottom of the panel.

**Fix — bottom scroll padding.** `_recompute_scroll_bounds` (both twins) now extends
`_content_h` by `BOTTOM_SCROLL_PAD = 300px` of empty space below the last row WHEN the
real row stack already overflows the visible window. That grows `max_scroll` so any
near-bottom row can be scrolled up far enough that its open dropdown fits inside the
visible list area. 300px comfortably clears the tallest popup (`DD_MAX_ROWS * DD_ROW_H`
≈ 10×24 = 240px) plus margin; the value is tunable via the file-local constant.

- The pad is added only when content overflows, so short lists that already fit don't grow
  a spurious scrollbar or phantom scroll into empty space.
- `_content_h` itself is extended (not a side field), so the scrollbar thumb fraction
  (`visible_h / _content_h`, draw path) stays correct — the thumb just gets slightly
  smaller on a padded list, which is fine.
- Applied identically in `_mod_tweaker_view.lua` (in-mission standalone) and
  `_mod_tweaker_state.lua` (keep sub-state). One edit point per twin
  (`_recompute_scroll_bounds`) covers both the normal list and the drilled-in advanced
  view, since both call it after setting `_content_h`.

No change to the rows=0 guard (`has_children and wtype ~= "header"`),
`plan_drill_children`, the v0.2.78 scrollbar thumb math, or the 0.2.79 menu-open sound.

## 0.2.79-dev (2026-06-23) — Mod Tweaker: native menu-open sound on view-enter

The Mod Tweaker view did not play the menu-open sound that VT2 menus — and the VMF
options menu specifically — play when they open. Added it so opening the Mod Tweaker
sounds the same as opening the settings menu.

**Sound + mechanism.** Vanilla `OptionsView.on_enter` fires
`WwiseWorld.trigger_event(self.wwise_world, "Play_hud_button_open")` on open
(`Vermintide-2-Source-Code/scripts/ui/views/options_view.lua:1615`); the VMF options
view fires the same `Play_hud_button_open` via `WwiseWorld.trigger_event` on its enter.
We now play that exact event on both Mod Tweaker twins' on-enter.

- **In-mission standalone view** (`_mod_tweaker_view.lua`): new `_play_open()` helper
  fires `Play_hud_button_open` through the existing `_play_event()` path (resolves a
  `wwise_world` off `music_world`, pcall-guarded). Called in `ModTweakerView:on_enter`
  right after `_rebuild()`.
- **Keep sub-state** (`_mod_tweaker_state.lua`): swapped the prior enter sound
  (`play_gui_lobby_button_00_heroic_deed`, inherited from the compendium sub-state) for
  the canonical `Play_hud_button_open`, routed through the parent hero_view's
  `self:play_sound()` (its `wwise_world` is the reliable handle at the keep).

Both paths are pcall-guarded, so a missing world or renamed event is silent, never a
crash. No change to the rows=0 guard, `plan_drill_children`, or the scrollbar.

## 0.2.78-dev (2026-06-23) — Mod Tweaker scrollbar: thumb position fixed (was inverted + overflowing) + real vanilla colors

**0.2.77 confirmed working for SIZE** — the local_offset sizing fix worked; the thumb now resizes
proportionally on overflow. Two issues remained, both fixed here by mirroring the native VT2
scrollbar exactly.

**1. Position was inverted and overflowed.** At the top of the menu (`scroll_value=0`) the thumb
sat at the BOTTOM of the track; scrolling down pushed it further down and off the track bottom.
The 0.2.77 code used a NEGATIVE offset (`offset[2] = -(track_h - th) * scroll_value`), which is
wrong for this node's coordinate system.

The mt_scrollbar scenegraph (and the list itself) is **+Y-up**: the view scrolls the list with
`list_node.offset[2] = +scroll_y` and documents "Positive Y shifts the stack UP (reveals lower
rows)" (`_mod_tweaker_view.lua:1752-1759`). `scroll_value = scroll_y/max_scroll` is therefore 0 at
the TOP of the content and 1 at the BOTTOM. For the thumb to read correctly it must sit HIGH at the
top and LOW at the bottom. Matched the native VT2 widget `UIWidgets.create_scrollbar`
(`ui_widgets.lua:2168-2386` — the exact widget the vanilla Options view uses on an identically
center-aligned node, `options_view_definitions.lua:316`), which positions its thumb with
`scroll_bar_box.offset[axis] = (scroll_length - thumb_length) * value` clamped to
`[0, end_position]` (`:2251-2259`). Corrected formula
(`_mod_tweaker_definitions.lua:1200-1235`):

```lua
local end_position = track_h - th                              -- max thumb travel
local current_position = end_position * (1 - clamp(scroll_value, 0, 1))  -- HIGH at top, 0 at bottom
ui_style.thumb.offset[2] = math.clamp(current_position, 0, end_position) -- never overflows
```

**Top/bottom clamp.** `offset[2]` is clamped to `[0, end_position]`, so the thumb's bottom-left
origin is always `>= 0` (never below the track bottom) and its top edge is
`offset + th <= end_position + th = track_h` (never above the track top). The thumb can no longer
run off either end.

**2. Track color was fabricated.** The `{70,70,70}` track grey was invented. Read the REAL vanilla
values from native `create_scrollbar` (`ui_widgets.lua:2286-2306`):
- **track** (`background`) default = `{255, 5, 5, 5}` (near-black) — now used (was the made-up
  `{70,70,70}`).
- **thumb** (`scroll_bar_box`) default = `Colors.font_button_normal` = `{255, 160, 146, 101}`
  (`colors.lua:1021-1026`, the warm tan) — gut already had this exact value since 0.2.76; it turns
  out to be the native default, so it is kept.

**Probe extended (both twins).** The `[mt:scrollbar]` dump now logs the thumb's RESOLVED `offset[2]`
(`_resolved_thumb_off`, written by the local_offset pass) and a computed **world-Y top + bottom**
line versus the track's world-Y span, plus `scroll_value`, so position is verifiable from log data:
on overflow the thumb should be flush at the track TOP at `scroll_value=0` and flush at the BOTTOM
at `scroll_value=1`, always inside `[track_y, track_y + track_h]`.

**Not regressed:** the v0.2.77 local_offset SIZING (sizes the thumb to
`track_h * clamp(thumb_frac, 0.06, 1)`), the `_max_scroll > 0` draw-gate, the thumb-drag input,
the `rows=0` guard, and `plan_drill_children` are all untouched.

## 0.2.77-dev (2026-06-23) — Mod Tweaker scrollbar: thumb now sizes + drags (offset_function moved to a local_offset pass)

**Symptom (user, in-game).** The scrollbar thumb was ALWAYS the full length of the track and could
not be dragged to scroll. The `[mt:scrollbar]` probe confirmed the thumb's `style.size = {8, 760}`
= the full 760px track height, regardless of how much the content overflowed.

**Root cause — the same `offset_function` / `local_offset` defect that burned the gut SLIDER 3x
(fixed v0.2.59).** The thumb's proportional sizing + scroll-position math lived in an
`offset_function` attached directly to the thumb's `rect` pass
(`_mod_tweaker_definitions.lua:1185`). But VT2's generic widget draw loop
(`ui_renderer.lua:521-555`) NEVER calls `offset_function` for `texture`/`rect`/`texture_uv` passes —
only a dedicated `pass_type = "local_offset"` pass invokes it (`UIPasses.local_offset.draw`,
`ui_passes.lua:4587-4593`, is literally just `pass_definition.offset_function(...)`). So the
thumb's sizing function silently never ran: the thumb kept its scenegraph style size
`{8, track_h}` = the full track every frame, leaving nothing shorter than the track to grab. The
0.2.76-dev note "thumb `offset_function` ... Unchanged; just no longer drawn" was wrong on that
point — the function was never firing in the first place.

**Fix.** Replaced the per-pass `offset_function` with a single `local_offset` pass placed BEFORE
the thumb `rect` pass, mirroring the working slider (`create_slider`,
`_mod_tweaker_definitions.lua:591-669`) and the native VT2 pattern
(`options_view_definitions.lua:1673-1695`). That pass mutates the thumb sub-style in place every
frame:

- `ui_style.thumb.size[2] = track_h * clamp(thumb_frac, 0.06, 1)` — proportional height,
  strictly `< track_h` on real overflow, so the thumb is now visibly shorter than the track.
- `ui_style.thumb.offset[2] = -(track_h - thumb_h) * clamp(scroll_value, 0, 1)` — slides the
  thumb down the track as you scroll.

The view still feeds `content.scroll_value` + `content.thumb_frac` each frame, gated on
`_max_scroll > 0` (`_mod_tweaker_view.lua:1801` / `_mod_tweaker_state.lua:1754`), so on a fitting
menu the whole widget stays hidden (correct, unchanged). The existing thumb-drag input path
(`_max_scroll > 0` block reading the scrollbar hotspot, both twins ~:1376/:1339) is unchanged —
it now has a sub-track-length thumb to drag against. Colors unchanged: tan thumb
`{255,160,146,101}`, track `{255,70,70,70}`.

**Probe extended.** The `[mt:scrollbar]` THUMB line now logs the RESOLVED thumb height (the
local_offset pass writes `content._resolved_thumb_h`), so a full-track value there immediately
flags the pass not running. The probe also fires once on each overflow-state TRANSITION inside
`_recompute_scroll_bounds` (`scroll-bound:overflow` / `:fits`), so the next repro captures the
overflow state — on_enter alone often sampled before the list had overflowed. Both twins.

**Not regressed:** the `_max_scroll > 0` draw-gate, the tan/grey colors, the normal-list `rows=0`
guard, and the 0.2.75-dev `plan_drill_children` nested-dropdown fix are all untouched.

## 0.2.76-dev (2026-06-23) — Mod Tweaker scrollbar: native-tan thumb (no more "solid grey column")

The user reported the scrollbar still drew as a solid grey column covering the whole track,
always max size, with no visible backdrop. The `[mt:scrollbar]` probe from 0.2.73-dev confirmed
the geometry path.

**1. Draw is gated on overflow.** Both twins' `_draw` already wrap the scrollbar
`UIRenderer.draw_widget(renderer, self._scrollbar)` in
`if self._scrollbar and (self._max_scroll or 0) > 0 then` (`_mod_tweaker_view.lua:1801` /
`_mod_tweaker_state.lua:1754`). `_max_scroll = max(0, content_h - visible_h)`
(`_recompute_scroll_bounds`), so when the content fits the window the WHOLE widget — track,
thumb, and hotspot passes — is skipped, exactly like the native VT2 scrollbar. The earlier
"full grey column even when nothing scrolls" was the pre-gate state the probe captured; the gate
is in place and is the single draw path (verified: exactly one `draw_widget(self._scrollbar)`
call per twin, both inside the gate).

**2. Proportional thumb on overflow.** When `_max_scroll > 0`, the draw sets
`thumb_frac = visible_h / content_h` (< 1), and the thumb pass's `offset_function`
(`_mod_tweaker_definitions.lua:1185`) sizes the thumb to `track_h * clamp(frac, 0.06, 1)` — always
strictly less than `track_h` on real overflow — so the track backdrop is visible behind/around
the thumb. Unchanged; just no longer drawn in the content-fits case where `frac` would clamp to 1.

**3. COLOR — the live fix this version.** The thumb was grey `{210,210,210}` — wrong hue and far
too bright, which read as the "solid grey column." Switched it to native VT2 tan
`{160,146,101}` (`font_button_normal`) so it matches the rest of the menu chrome. The track stays
mid-grey `{70,70,70}` (~55 levels over the probe-measured `{15,15,15}` background backing, and
clearly distinct from the tan thumb). Shared build lives once in `build_scrollbar_rect`
(`_mod_tweaker_definitions.lua:1209-1210`); both twins consume it. EXACT RGB is an in-game
eyeball call per the no-speculate-on-appearance rule — these are native-matched defaults.

**Not regressed:** the `[mt:scrollbar]` probe stays in place for re-verify; the normal-list
`rows=0` guard (`has_children and wtype ~= "header"`) and the 0.2.75-dev `plan_drill_children`
nested-dropdown fix are untouched.

## 0.2.75-dev (2026-06-23) — Mod Tweaker: VMF dropdowns nested 3-deep now show their options

**Symptom.** The wt anim picker's per-attack dropdowns (and any VMF dropdown sitting three
levels deep) opened empty / showed `?` in the Mod Tweaker, even though VMF's own native menu
renders them full.

**Root cause — a NESTING-DEPTH navigation bug, NOT a wrong options read.** gut already reads a
dropdown's option list the SAME way VMF's native options view does: the option array is at
`node.options` (top-level on the flattened `vmf.options_widgets_data` entry), and each entry's
label/value are `option.text` / `option.value` — byte-for-byte VMF's
`initialize_dropdown_data` (`new_data.options = data.options`) and its render loop
(`for i, option in ipairs(widget_definition.options) do options_texts[i] = option.text;
options_values[i] = option.value`). gut reads exactly that via `_nf(w, "options")` →
`_nf(o, "text")` / `_nf(o, "value")` (`_mod_tweaker_state.lua:543/550-554`). That read was never
the problem and is unchanged.

The wt anim picker wires its dropdowns as `checkbox (depth 1) → set-group (depth 2) →
per-attack dropdown (depth 3)`. The gear-drill's child loop only ever rendered the drilled
parent's **direct** children (a hard-coded single `depths[j] == pdepth + 1` level): drilling the
checkbox showed the depth-2 set-GROUP headers, and the loop never descended to build the depth-3
dropdown nodes. The dropdowns therefore never existed as rows, so their (correctly-read) options
were never surfaced — the `?` / empty was the **absence of the row**, not an empty option list.

**Fix.** New shared planner `defs.plan_drill_children` (`_mod_tweaker_definitions.lua`) walks the
WHOLE subtree under the drilled parent using the SAME group-collapse / gear-parent rules as the
normal list loop, rebased so the parent is row-depth 0 and a flat-depth-d node renders at
row-depth `d - pdepth`. A child that is itself a `group` honors the user's expand state (collapsed
groups hide descendants inline, expanded groups reveal them); a non-group node with deeper
children gets a gear so it can be drilled one level further. So the user can now drill the
checkbox → expand a set-group → see and pick its dropdowns, and selecting an option stages +
applies through the existing `_commit_dropdown` path unchanged.

Both twins (standalone `ModTweakerView` in-mission, `HeroViewStateModTweaker` keep sub-state)
call the shared planner identically. A new `:_group_key(node, category)` method (added to both
twins, mirroring the original inline gid) is shared by `_build_node_row` and the planner's
`is_expanded` predicate so the rendered group row and the planner agree on the exact expand key.

**Not regressed:** the normal-list `rows=0` guard (`has_children and wtype ~= "header"`,
`_mod_tweaker_state.lua:700` / `_mod_tweaker_view.lua:570`) is untouched — the planner runs only
inside the `self._drill` branch. The header exclusion is intentionally not replicated in the
planner because a VMF per-mod header only ever appears at top level (depth 0), never inside a
drilled subtree. `luacheck`: 0 errors across all three files.

## 0.2.74-dev (2026-06-23) — Mod Tweaker scrollbar POSITION + COLOR fix (from REAL probe data)

The 0.2.73-dev `[mt:scrollbar]` probe gave us the runtime truth. Two problems, both fixed off
measured values (no more inference):

**1. POSITION (the real bug) — root cause: wrong anchor.** The bar parented to `list_mask` and
right-aligned with a `-30` inset. But native `list_mask` is a **left-aligned 1400px-wide node**
(== `WINDOW_WIDTH`) sitting at `+18` on the centered `background_frame`
(`options_view_definitions.lua:274-287`), so its **right edge juts ~18px PAST the visible panel's
right edge**. Right-aligning the bar to that off-panel edge made its on-screen X depend on a brittle
absolute offset: the probe measured world x **-12** (off the left) when the menu sat at origin
`{0,0}`, and world x **1638** (right edge of the over-wide mask, on/over the frame border) when the
menu was at `{260,90}` — not deterministic, not anchored to anything the player sees.

Fix: re-anchor `mt_scrollbar` to **`background_frame`** (the decorated panel — centered, same
1400×900 as `background`), right-aligned with a small `-12` X inset (matching how native parents its
own `scrollbar_root` to `background`, not to the over-wide list_mask), vertical-centered with the
list-window height (760). The bar's world position is now identical in BOTH the standalone-view and
keep-sub-state presentations regardless of menu world position, and sits in the panel's right gutter
just inside the frame border. The thumb-drag math and the `offset_function` thumb travel are
unaffected — the node's world Y is numerically identical to the old list_mask-anchored value
(frame_bottom + 70 either way).

**On_screen-flag interpretation (why the probe said `false` in BOTH states — and it was a red
herring).** `math.point_is_inside_2d_box` uses **strict** `<`/`>` (`math.lua:142-143`). The old
probe tested the bar's bottom-left ORIGIN against the `list_mask` box; because the bar shares
`list_mask`'s vertical span, the bar's bottom-left Y **equals** the box's bottom Y, so `pos[2] >
lower[2]` is `false` → `on_screen=false` even when the bar is perfectly visible. So the `false` was a
strict-shared-edge artifact, not proof of off-screen. The probe is now corrected to test the bar's
**CENTRE** against **`background_frame`** (the visible panel), making the flag meaningful for the
next verify.

**2. COLOR — calibrated to the measured `{15,15,15}` background.** The probe confirmed the real
`background` chrome the bar draws over is `{15,15,15}` (not the `~{10,10,10}` the 0.2.72 comment
assumed). The old track `{30,30,30}` is only ~15 levels above that = barely distinguishable.
Track → `{70,70,70}` (clearly lighter than `{15,15,15}`); thumb stays bright at `{210,210,210}`
(reads strongly against the `{70,70,70}` track). EXACT RGB is an in-game eyeball call per the
no-speculate-on-appearance rule — these are reasonable high-contrast starting values to nudge after
a live look. **Thumb DYNAMIC SIZING is untouched** (probe confirmed frac 0.821 → 624px is correct).

The `[mt:scrollbar]` probe stays in place for the next verify. Shared scrollbar build (position +
color) lives once in `_mod_tweaker_definitions.lua` (`build_scrollbar_rect` + the `mt_scrollbar`
scenegraph node), so both twins inherit it; only the per-twin probe `on_screen` block was edited in
both files. The `rows=0` guard is untouched.

## 0.2.73-dev (2026-06-23) — Mod Tweaker scrollbar DIAGNOSTIC PROBE (instrument only, NO behavior change)

The scrollbar is still reported as "doesn't work" + "wrong color" after the 0.2.72-dev contrast
fix. That fix used INFERRED colors — it assumed the menu `background` was `~{255,10,10,10}` from a
code comment and never MEASURED it. (The native `background` chrome rect is actually
`{255,15,15,15}`; only the top/bottom panels are `{10,10,10}`.) Before touching colors again, we
need the REAL runtime render-state from an in-game repro.

This release adds a one-time-per-open `[mt:scrollbar]` debug dump (gated on `enable_debug_logging`,
fired from the SAME site as the existing `[mt:dump]` probe — `on_enter` / `substate_on_enter`) in
BOTH twins (`_mod_tweaker_view.lua` ESC-flow standalone view + `_mod_tweaker_state.lua`
`HeroViewStateModTweaker` keep sub-state). The dump logs:

- **Background chrome** `chrome[1]` resolved color `{A,R,G,B}` + scenegraph world position/size — the
  actual contrast baseline (no longer inferred). Also logs the top/bottom panels + list_mask.
- **Scrollbar TRACK + THUMB** resolved colors, scenegraph world position/size, and each style's z
  (`offset[3]`) for draw-order.
- **Scroll math:** `_content_h`, `_visible_h`, `_max_scroll`, `track_h`, the computed `thumb_frac`
  (= visible/content, same formula as the draw path), the clamped frac, the resulting `thumb_px`,
  and `will_draw` (the bar only draws when `_max_scroll > 0`).
- **On-screen check:** whether the `mt_scrollbar` node's world X/Y falls inside the `list_mask` panel
  box (off-panel = invisible to the eye even if "drawn").

NO scrollbar color/logic/geometry was changed — this is purely an instrument so the next repro log
reveals (a) the real background color, (b) whether the bar is drawn and where, and (c) whether the
thumb height is sane. Twin discipline preserved: identical probe body in both files.

## 0.2.72-dev (2026-06-23) — Mod Tweaker scrollbar now VISIBLE (contrast fix); confirmed thumb already dynamic + recomputed on collapse/expand

The scrollbar was reported as "wrong" — looking like there was no bar, and not appearing to
resize on collapse/expand. Diagnosis split the report into two halves:

- **Thumb sizing / collapse-expand recompute: ALREADY CORRECT (no code change).** The thumb is
  genuinely dynamic. `content.thumb_frac = visible_h / content_h` is recomputed every frame
  (`_mod_tweaker_view.lua:1682`, twin `_mod_tweaker_state.lua:1646`) from `self._content_h`, and
  the defs `offset_function` converts it to a live thumb height `th = track_h * frac`
  (`_mod_tweaker_definitions.lua:1099-1104`) — the native `track_length * (visible/total)` formula.
  `_content_h` is itself recomputed by `_build_rows` on EVERY collapse/expand/drill/tab-switch
  (`view:582-584`, `state:712-713`), which the group-header click funnels through. So the thumb
  grows when a group collapses (less content) and shrinks when it expands (more content) without
  any extra wiring. This half of the report was not a real bug.

- **Visibility / color: THE REAL CAUSE — fixed.** The track color was `{255,5,5,5}` — DARKER than
  gut's `background` chrome fill (`~{255,10,10,10}`), so the track was effectively invisible against
  the panel (exactly the user's "bar equals the menu background" guess). The native scrollbar only
  reads in the real Options menu because its track sits over a lighter list backing; gut's
  `mt_scrollbar` draws over the raw dark background. The thumb `{255,160,146,101}` was the dim idle
  `font_button_normal` tan with weak contrast and no hover-brighten. Fix raises the track to
  `{255,30,30,30}` (now LIGHTER than the background) and the thumb to `{255,200,200,200}` (bright,
  clearly visible). Single edit in the SHARED `_mod_tweaker_definitions.lua:1110-1121` scrollbar
  factory (`build_scrollbar_rect`), so it covers both presentations at once.

Twin discipline + the `rows=0` guard (`has_children and wtype ~= "header"`) are untouched in both
`_mod_tweaker_view.lua` (ESC-flow standalone) and `_mod_tweaker_state.lua`
(`HeroViewStateModTweaker` keep sub-state).

## 0.2.71-dev (2026-06-22) — Mod Tweaker polish: ON/OFF flicker fix, width-based tab pagination (no more "More 1/2"), bare-text APPLY, native slider glow, full hover sounds (both twins, rows-guard intact)

Five contained Mod Tweaker fixes. Every view/draw/scenegraph change lands in BOTH twins
(`_mod_tweaker_view.lua` = ESC-flow standalone, `_mod_tweaker_state.lua` =
`HeroViewStateModTweaker` keep sub-state) identically; shared widget factories in
`_mod_tweaker_definitions.lua`. The `rows=0` guard (`has_children and wtype ~= "header"`) is
untouched in both twins.

1. **ON/OFF toggle flicker FIXED.** A single physical click on a checkbox/boolean row was
   flipping `content.flag` on/off/on across several frames ("negotiating" flicker). Root cause:
   the rows share the `mt_list_start` node, which keeps `on_release`/`on_left_release` latched
   true for several consecutive draw frames, and the handler's unconditional
   `c.flag = not c.flag` re-inverted the flag once per latched frame (the displayed word follows
   `content.flag` directly via the defs `on_text`/`off_text` passes, so every extra toggle is
   visible). Fix = a per-row `row._toggle_armed` release edge-latch so the toggle fires exactly
   ONCE per physical release, then clears when all three hotspots' (`hotspot`/`dec`/`inc`)
   release flags drop. Mirrors the existing `row._was_hovered` hover debounce. Checkbox branch
   of `_handle_input` in both twins.

2. **"More 1/2" pagination dropped — paginate on MEASURED width, not tab COUNT.** Tabs are
   text-aware (variable width via `_layout_tabs`), so the old `total > MAX_TABS` (=8) count test
   over-paginated, showing a "More 1/2" tab even when every label fit. The `_rebuild` pagination
   block now pre-measures each tab label the SAME way `_layout_tabs` does (create_tab style =
   `hell_shark` / size 20 / `upper_case`; `UIFontByResolution` + `UIRenderer.text_size` + a 20px
   gap each) and only paginates when the sum exceeds the usable strip
   (`defs.window.w` 1400 − x0 anchor 65 − 120px right margin). When it fits, `per_page = total`
   so ALL tabs show and no More tab is built. The measure is pcall-guarded → falls back to "fits"
   (no pagination) on a borrowed-renderer failure. `MAX_TABS` survives only as the per-page size
   for a genuine overflow; the "More" tab-click branch + paged hint stay (dead but harmless
   unless a future overflow re-triggers them).

3. **APPLY button box REMOVED — bare text + hover.** Dropped the filled `rect` bg pass and the
   1px `border` pass from `create_apply_button` (defs), keeping only the `hotspot` (click +
   hover) and `text` passes. The `bg`/`border` STYLE tables are kept so both twins' per-frame
   `asty.bg.color` / `asty.border.color` writes still index live tables (now harmless no-ops);
   the gold/grey enabled-disabled text-color feedback and the gated hover sound are retained.

4. **Native slider hover-GLOW restored.** gut already had a `thumb_hover` (`slider_thumb_hover`)
   texture pass gated on `c.track_hs.is_hover`, but it was sized at the BASE thumb's 14x27 — an
   invisible same-size overlay, not the glow. The native glow is the WIDER 34x25
   `slider_thumb_hover` atlas sprite (`gui_settings_atlas.lua:396`) centered on the 14px base
   thumb and drawn on top only while hovering (`options_view_definitions.lua:1720-1739`,
   `:2062-2073`). Defs now size `thumb_hover` at 34x25 (`THUMB_HOVER_W/H`), center it vertically
   on the row and horizontally on the base thumb (the `local_offset` pass adds
   `THUMB_W/2 − THUMB_HOVER_W/2`), and set `masked = false` (the borrowed renderer has no stencil;
   the sprite is fully inside its UV rect). Both sprites are atlas-backed and resident → safe on
   the borrowed renderer (per `reference_vt2_options_widgets_raw_materials`).

5. **Hover sounds wired on tabs, APPLY, and exit-X.** Clicks already fired `_play_click()` on
   every commit (toggle/arrow/dropdown-select/slider-release/tab-switch/APPLY/gear/exit). Hover
   sounds previously fired ONLY for list rows (`_apply_row_hover`). Added edge-debounced
   `_play_hover()` on the hover-ENTER edge for the top tabs (`tab._was_hovered` in the tab-tint
   loop), the APPLY button (`self._apply._was_hovered`, gated on `enabled` so the greyed button
   stays silent), and the exit-X (`self._exit._was_hovered`) — all in both twins' `_draw`. No
   change to `_wwise_world` / `_play_event` (resolution off `music_world` is already correct +
   pcall-safe).

## 0.2.70-dev (2026-06-22) — Mod Tweaker PHASE 4: STAGED-change model + bottom-right APPLY button (both twins, rows-guard intact)

PHASE 4 from the implementation spec. Editing a setting no longer writes live — every edit
(toggle / stepper / slider drag / dropdown select / typed number field) now stages into a
**pending buffer**, and a native-style **APPLY** button (bottom-right of the bottom panel)
commits the whole buffer at once. Exiting the menu **discards** any unapplied edits. Rows
**display the pending value** while it's pending (so a staged toggle/slider/dropdown shows the
new value, not the old live one). Modeled on native Options, which stages all edits in
`changed_user_settings` and only writes on APPLY (`options_view.lua:1789-1939, 3129-3196`). No
DEFAULT/reset button (deliberately omitted per spec).

How the buffer works:
- `self._pending[mod_id][setting_id] = staged_value`. Keyed by **mod_id** (a stable string),
  NOT the category table — category tables are re-created on every `_rebuild`
  (`_vmf_categories`), so keying by the table would lose the buffer on a tab switch. mod_id
  survives, which also gives **per-category isolation** for free: switching tabs away and back
  preserves that category's staged edits, and APPLY commits only the active category's buffer.
- **`stage_set(category, id, value)`** — every row WRITE routes here (was a live `_cat_set`).
  Records the value + refreshes the APPLY dirty state. Does NOT set `self._dirty`.
- **`get_staged(category, id, live_value)`** — every row READ/repaint routes here. Returns the
  staged value if pending, else the live value (mirrors native `_get_setting` `assigned(...)`).
  Wired into the checkbox `flag`, slider `value`, and dropdown `current_selection` reads in
  `_build_node_row`, so a rebuilt row reflects its staged edit instead of snapping back to live.
- **`apply_pending(category)`** — the APPLY click. The **ONLY** place `_cat_set` runs on edit:
  it loops the buffer through `_cat_set` (so each mod's `on_setting_changed` still fires —
  ct's 25-coin snap, etc.), clears the buffer, sets `self._dirty` (so the TOML still exports on
  exit), greys the button, and `_build_rows` repaints from the new live values.

APPLY button:
- New `mt_apply` scenegraph node — clone of native `apply_button`
  (`options_view_definitions.lua:344-357`): parent `background_bottom_panel`, right/top
  aligned, position `{-30,-7}`, size `{150,30}`. Native's `reset_to_default` (DEFAULT) sibling
  (`:358-371`) is **not** cloned.
- Hand-built widget (`create_apply_button`, defs) — `rect` bg + `border` + hotspot + centered
  text — NOT `UIWidgets.create_text_button` (atlas/material backing can miss on the borrowed
  renderer; same reasoning as the tabs). Both passes are material-lookup-free (`border` uses
  only `UIRenderer.draw_rect`, `ui_passes.lua:1245-1258`), so they resolve on the borrowed
  renderer. Label from `menu_settings_apply` when it localizes cleanly, else literal "APPLY".
- Enabled/greyed (`_update_apply_button`, recomputed each draw frame): **gold** text
  (`cheeseburger` `{255,255,168,0}`, `colors.lua:85`) + brighter border when the active
  category's buffer is non-empty (`next(pending) ~= nil`); dim grey + faint border + click
  suppressed when empty. Hover brightens the bg fill when enabled. Mirrors native
  `update_apply_button` (`options_view.lua:3129-3140`).

Discard semantics: because nothing was written live, exit = drop the buffer (`self._pending =
{}` in `on_exit`). No native `apply_changes(original_*)` re-apply is needed (that exists only
for native's live video-preview). `self._dirty` (the auto-save-to-log trigger) is set ONLY by
`apply_pending` — a buffer that was never applied leaves `_dirty` false, so exiting with only
pending edits correctly does **not** export.

Audit constraint (load-bearing): every former live-write site — checkbox toggle, slider
commit, dropdown commit, and the typed-number `_commit_edit` — now calls `stage_set`; `_cat_set`
is called from `apply_pending` ONLY (verified by grep in both twins). Any row still reading live
(not `get_staged`) would visually snap back after an edit — the three editable reads were all
converted.

Implemented IDENTICALLY across the two verbatim twins (`_mod_tweaker_view.lua` = standalone
in-mission view; `_mod_tweaker_state.lua` = HeroView keep sub-state): the five staging methods
(`stage_set` / `get_staged` / `_active_category_dirty` / `_update_apply_button` /
`apply_pending`), the `_cat_key` helper, the buffer init, the three buffer-first reads, the four
staged writes, the APPLY input handler, the APPLY per-frame styling, the APPLY draw, and the
discard-on-exit are all the same modulo the class-name prefix. The one deliberate difference:
the view defines the staging helpers AFTER its `_cat_set`/`_play_click` file-locals (the view
declares them after the class; placing the helpers right after the class would capture the
GLOBAL nil `_cat_set` — forward-reference trap), whereas the state declares `_cat_set` before its
class so it places them earlier. Behaviour is byte-identical. Shared APPLY widget factory
(`create_apply_button`) + scenegraph node live once in `_mod_tweaker_definitions.lua`. The
`rows=0` build guard (`has_children and wtype ~= "header"`) is unchanged in BOTH twins. No new
hooks. luacheck: 0 errors. **Needs an in-game eyeball.**

## 0.2.69-dev (2026-06-22) — Mod Tweaker PHASE 3: real DROPDOWNS (single down arrow → popup option list → select/close), both twins, rows-guard intact

PHASE 3 from the implementation spec. Dropdown-type settings are now a REAL dropdown
instead of a `[<]`/`[>]` stepper carousel: the collapsed row shows the selected value with a
single **down-pointing arrow** on the right; clicking the row opens a **popup list** of the
options; clicking an option **sets the value + closes**; click-away or **Esc closes** without
committing. Modeled on native `create_drop_down_widget`
(`options_view_definitions.lua:2299-3047`). Steppers, sliders, checkboxes, and the gear
drill-down are untouched.

Built on gut's borrowed renderer with only atlas-resident textures (no raw non-atlas
materials): the collapsed arrow is `drop_down_menu_arrow` / `drop_down_menu_arrow_clicked`
(`gui_settings_atlas`, the same atlas as the slider thumb + stepper arrows; arrow box 31×15,
confirmed `gui_settings_atlas.lua:172`), flipped vertically (`uvs {{0,1},{1,0}}`) to point UP
while open. The popup highlight is `playerlist_hover` (`gui_menus_atlas`, the same sprite gut
already uses for row hover + the gear); the popup background panel + shade are plain `rect`
passes (the borrowed renderer lacks `rect_masked` — same substitution gut uses for the
slider track / separator).

The popup is its OWN overlay widget on a new `mt_dropdown` scenegraph node (child of `mt_list`,
so it scrolls with the rows but draws LAST, after the rows + scrollbar, OUTSIDE the cull loop
— so it overlays everything and is never clipped by the `list_mask`). This is the
cosmetics_tweaker glow-picker "own overlay scenegraph" pattern. While a dropdown is open it's
**modal**: `_handle_input` short-circuits to the popup so no other row reacts. One dropdown
open at a time (`self._open_dropdown`); the buffer is cleared on every list rebuild (tab
switch / drill / collapse), same as the type-edit teardown.

Open / select / close mechanics:
- **Open** — click the collapsed row's right field strip (`content.hotspot.on_left_release`) →
  `_open_dropdown_popup`: sets `content.active` (flips the arrow up), scrolls the visible window
  so the current selection is in view, builds the popup widget, plays `Play_hud_select`.
- **Select** — click a visible option row (`content.opt_<k>.on_left_release`) →
  `_commit_dropdown`: maps the visible slot `k` to the absolute option index via `start_index`,
  writes through the existing `_cat_set` path (so the mod's `on_setting_changed` still fires),
  updates the collapsed-row value text, closes.
- **Close without commit** — click-away (`Mouse.released(0)` not over an option) OR the first
  **Esc** (highest-priority branch in `update`, above the type-edit and drill ESC handlers).
- **Long lists** — popup caps at 10 visible rows; the mouse wheel over an open list scrolls the
  option window (`start_index ± 1`) and rebuilds the popup.

Implemented IDENTICALLY across the two verbatim twins (`_mod_tweaker_view.lua` = standalone
in-mission view; `_mod_tweaker_state.lua` = HeroView keep sub-state) — the six new dropdown
methods, the modal short-circuit, the row-loop open branch, the ESC-close branch, the
`_build_node_row` routing, the `_build_rows` clear, and the `_draw` popup overlay were all
verified byte-identical between twins (modulo the class-name prefix). Shared widget factories
(`create_dropdown` + `create_dropdown_list`) live once in `_mod_tweaker_definitions.lua`. The
`rows=0` build guard (`has_children and wtype ~= "header"`) is unchanged in BOTH twins. No new
hooks (mod-lint PASS: 0 duplicate hooks). **Needs an in-game eyeball.**

## 0.2.68-dev (2026-06-22) — Mod Tweaker LAYOUT batch finalized: equipment-cog gear + control-column gutter, measured tabs, native scrollbar (both twins, rows-guard intact)

LAYOUT-batch finalization pass on the Mod Tweaker. The three layout items below were
landed in 0.2.67-dev as part of the larger polish+layout pass; this version pins them as
the verified LAYOUT deliverable after a both-twins parity + native-atlas audit. No new
behavioral subsystems — the option rows still cycle via the `[<]`/`[>]` stepper and every
edit still writes live (PHASE 3 popup dropdown / PHASE 4 staged APPLY remain deferred).

All three were verified IDENTICAL across the two verbatim twins (`_mod_tweaker_view.lua` =
standalone in-mission view; `_mod_tweaker_state.lua` = HeroView keep sub-state) with the
shared widget pieces living once in `_mod_tweaker_definitions.lua`. The `rows=0` build guard
(`has_children and wtype ~= "header"`) is unchanged in BOTH twins. **Needs an in-game eyeball.**

- **Gear = equipment-menu cog (atlas-audited).** `create_gear_button` (defs) uses `cog_icon`
  (idle) / `cog_icon_selected` (hover), both confirmed present in `gui_menus_atlas`
  (`gui_menus_atlas.lua:1586`/`:1600`, authored 58×58) — the proven-resident atlas on the
  borrowed renderer. `texture_size` rescales the 58px sprite into the 26px gear box; a
  `cog_hover` pass gated on the gear hotspot highlight does the idle→selected swap. Shared
  factory, so both twins inherit it identically.
- **Control column left-shifted into its own gutter.** `RA = ROW_W - (GEAR_SIZE+24)` (=
  `ROW_W-50`); every arrow/value/track column derives from `RA`, so all recede 50px while the
  gear (`ROW_W - GEAR_SIZE - 10`) sits alone in the right-edge gutter — fixing the prior
  stepper-inc-arrow ↔ gear collision. `GEAR_SIZE` is defined above `RA` so the shift math can
  reference it; applied unconditionally so all rows stay column-aligned. Shared in defs.
- **Text-aware (measured) tabs.** `_layout_tabs()` (present + byte-identical in both twins)
  measures each tab label via `UIRenderer.text_size(renderer, text, font[1], scaled)`
  (`font,scaled = UIFontByResolution(text_style)`, uppercased to match the rendered string)
  and packs the tab scenegraph nodes left-to-right with a literal 20px gap, exactly like
  native (`options_view.lua:986-994`). pcall-guarded so a measure failure leaves the
  fixed-width fallback layout untouched.
- **Native scrollbar colors + dynamic thumb.** `build_scrollbar_rect` (defs): track
  `{255,5,5,5}`, thumb `{255,160,146,101}` (`font_button_normal` @255). Thumb height =
  `track_h * thumb_frac` clamped `[0.06,1]`; both twins set
  `thumb_frac = visible_height / total_content_height` each frame, and the bar draws only when
  content overflows (`max_scroll > 0`), so it's hidden when `thumb_frac ≥ 1`.

## 0.2.67-dev (2026-06-22) — Mod Tweaker native-fidelity POLISH + layout pass (slider fill, group bg, nesting indent, number-field bevel, Enter→chat, gear texture, control-column shift, measured tabs, scrollbar)

Native-fidelity polish + layout pass on the Mod Tweaker, all derived from the VT2
`OptionsView` / `options_view_definitions` source. Shared widget pieces live once in
`_mod_tweaker_definitions.lua` (so both verbatim twins inherit them); the depth-threading,
chat-block, and measured-tab logic were added IDENTICALLY to BOTH twins
(`_mod_tweaker_view.lua` = standalone in-mission view, `_mod_tweaker_state.lua` = HeroView
keep sub-state). The `rows=0` build guard (`has_children and wtype ~= "header"`) is
unchanged in both twins. **Needs an in-game eyeball.**

### PHASE 1 — Polish

- **Slider yellow fill removed (native parity).** Native sliders have NO growing colored
  fill — only the thumb conveys position over a flat dark track
  (`options_view_definitions.lua:1675-1752`). Deleted the `fill` pass, its style, and the
  per-frame fill-width driver in the slider's `local_offset` pass; recolored the track from
  `{255,35,35,35}` to native `slider_box` near-black `{255,5,5,5}`. The thumb is unchanged.
- **Group-header tinted bar removed; larger colored title kept.** Deleted the `bg` rect pass
  + style on `create_group_header` (and matched it on `create_back_row` for consistency).
  The font-22 `font_title`-colored indicator + label are now the sole group differentiator,
  matching native (which has no tinted header bar).
- **Per-depth leading indent for nested child rows.** New `INDENT_PER_DEPTH = 24` constant;
  each factory (`create_checkbox` / `create_slider` / `create_stepper` /
  `create_section_title` / `create_group_header`) now takes a trailing `depth` arg and
  indents ONLY the left label x by `24*depth`, narrowing the label clamp width by the same
  amount so indented labels still terminate before the controls. The right-anchored control
  columns (arrows / value / track / gear) are untouched and stay column-aligned. Both twins
  thread `depths[i]` from `_build_rows` into `_build_node_row` and on into the factories
  (drill children render at depth 1 under their depth-0 parent).
- **Dark bevel behind the editable number field.** Native `input_field_background` is two
  stacked `rect_masked` passes (outer `{200,0,0,0}` 52px + inner `{255,10,10,10}` 50px one z
  up) under the value text. The borrowed renderer lacks `rect_masked`, so plain `rect`
  passes substitute (gut's established swap). Always-on; the transient `value_focus_bg`
  editing highlight had its z bumped 1→3 so it still layers over the bevel while typing.
- **Enter commits and never opens chat.** While a number field is being edited, the loop now
  re-asserts `Managers.chat:block_chat_input_for_one_frame()` every frame (pcall-guarded,
  `ChatGuiNull`-safe). The chat `chat_input` service is an independent read of keyboard
  Enter that gut's own `Keyboard.released(13)` commit can't block; the engine-sanctioned
  per-frame block (`chat_manager.lua:390-397`) suppresses chat activation for the whole edit
  (Enter-commit AND stray `y`/letters) and self-clears when editing ends. Existing
  Enter→commit / Esc→cancel handling is unchanged.

### PHASE 2 — Layout

- **Gear swapped to the equipment-menu cog.** `create_gear_button` now uses `cog_icon` (idle)
  / `cog_icon_selected` (hover) from `gui_menus_atlas` (the proven-resident atlas), rescaled
  into the 26px gear box, with a hover-swap pass gated on the gear hotspot's highlight. Was
  `cogwheel_small`.
- **Control column left-shifted to give the gear a gutter.** `RA` (the right anchor every
  arrow/value/track column derives from) now recedes 50px: `RA = ROW_W - (GEAR_SIZE+24)`.
  This opens a clean right-edge gutter where the gear (`ROW_W - GEAR_SIZE - 10`) sits alone,
  fixing the old collision between the stepper inc arrow and the gear. `GEAR_SIZE` was
  promoted above `RA` so the shift math can reference it. Applied unconditionally so all
  rows stay aligned. The exported `gear_col_w` (50) already equals the shift.
- **Text-aware (measured) tab widths.** New `_layout_tabs()` in both twins measures each
  tab's label via `UIRenderer.text_size(renderer, text, font[1], scaled)` (font from
  `UIFontByResolution(text_style)`, uppercased to match the rendered string) and packs the
  tab scenegraph nodes left-to-right with a literal 20px gap, exactly like native
  (`options_view.lua:986-994`). pcall-guarded — a measure failure leaves the fixed-width
  fallback untouched.
- **Scrollbar native colors.** Track `{150,12,12,12}`→`{255,5,5,5}`; thumb
  `{255,160,160,160}`→`{255,160,146,101}` (`font_button_normal` @255). The dynamic thumb
  size (`track_h * thumb_frac`, `[0.06,1]` clamp) and the per-frame
  `thumb_frac = visible_height / total_content_height` set by the view are unchanged; the
  bar is already drawn only when content overflows (`max_scroll > 0`), so it's hidden when
  `thumb_frac >= 1` as specced.

### Deferred (not in this build)

- **PHASE 3 (real popup dropdown) and PHASE 4 (staged-change model + APPLY button) are NOT
  in 0.2.67-dev.** Both are large behavioral subsystems that change the menu's input/write
  model (a modal popup list with its own scroll + click-away; converting every row from
  live-write to a staged buffer committed only on APPLY). They warrant their own in-game
  iteration loop rather than landing blind alongside the low-risk polish/layout pass. The
  option rows still cycle via the `[<]`/`[>]` stepper, and every edit still writes live.

## 0.2.66-dev (2026-06-22) — Mod Tweaker sliders: click-to-type the numeric value (Enter/focus-loss commit, clamp + step-snap)

Additive type-to-edit on every Mod Tweaker slider/numeric row, mirroring VMF's typeable
popup but inline in the value column. The drag, the `[<]`/`[>]` arrow stepping, and the
`rows=0` build guard (`has_children and wtype ~= "header"`) are all unchanged — typing is
a purely additive third input path that is suppressed only while a field is focused.

Shared widget pieces live once in `_mod_tweaker_definitions.lua` (so both verbatim twins
inherit them); the focus/keystroke/commit logic was added IDENTICALLY to BOTH twins
(`_mod_tweaker_view.lua` = standalone in-mission view, `_mod_tweaker_state.lua` =
HeroView keep sub-state). Needs an in-game eyeball.

### Added
- **Click the slider's value to type a number directly.** A new `value_hs` hotspot over
  just the value box (separate from the track/arrow hotspots) focuses the field on click;
  digits, `.` (when the slider has decimals), and `-` (only when the range allows
  negatives) are accepted, Backspace trims, 16-char cap — the exact VMF filter
  (`vmf_options_view.lua:4532-4556`). Only one row edits at a time (`self._editing_row`).
- **Edit cursor + focus highlight while typing.** A faint highlight behind the value box
  (`value_focus_bg`) marks the focused field, and a thin caret bar (`caret`) pulses at the
  end of the typed text. Both are driven every frame by the slider's existing
  `local_offset` pass (rect passes ignore their own `offset_function`, so the caret x +
  pulsing alpha + highlight alpha are mutated there, like the thumb). Caret x is measured
  via `UIRenderer.text_size`; invalid/out-of-range input red-tints the value text
  (`{255,255,70,70}`, VMF parity); a trailing bare `.` is allowed so typing can continue.
- **Commit on Enter or focus-loss; cancel on Escape.** Enter (`Keyboard.released(13)`) or a
  click outside the value box (`Mouse.released(0)`) commits; Escape (`Keyboard.released(27)`)
  — intercepted in `update` BEFORE the menu-close/drill-out so the first Esc cancels the
  edit — restores the prior value. On commit the typed number is clamped to `[min,max]` and
  snapped to the slider's `step` grid (same math the drag/arrow paths use), then run through
  gut's existing `_cat_set` + re-read so any mod-side snap (e.g. ct's 25-coin rounding) is
  reflected. An in-progress edit is abandoned on any list rebuild (tab switch / drill /
  group collapse) so no stale `_editing_row` survives.

## 0.2.65-dev (2026-06-22) — Mod Tweaker native-fidelity layout pass (title removed, tabs full-band, arrows column-aligned)

Five native-layout fixes derived from the VT2 `OptionsView` source, plus the keep
separator shift. All shared layout changes live once in `_mod_tweaker_definitions.lua`
(so they land in BOTH verbatim twins automatically); the title-widget removal touched
both twins (`_mod_tweaker_view.lua` + `_mod_tweaker_state.lua`) identically; the
separator shift is in `gui_tweaker.lua`. The rows=0 guard (`has_children and
wtype ~= "header"`) is unchanged and still present in both twins. Visual — needs an
in-game eyeball to confirm the exact placement.

### Changed
- **"MOD TWEAKER" title removed entirely (A/B).** Native Options has NO title text in
  the top band — the tab buttons span the whole band. Deleted the `mt_title` scenegraph
  node, the `build_title` factory, and every `self._title` build/draw/teardown in both
  twins. Undid the v0.2.64 band-split: tabs now occupy the FULL 50px top band,
  bottom-aligned and lifted +9px off the panel bottom, starting at x=65 — matching
  native `button_pivot` (`options_view_definitions.lua:204-217`).
- **Tab strip restored to the native full-band layout (B).** Tab nodes parent to
  `background_top_panel`, bottom-aligned, box height 30 (native tab box), x0=65, gap 20.
- **Inter-tab gap = native 20 (C).** Matches `options_view.lua:993` (`x += text_w + 20`).
  (Tabs remain fixed-width slots — a deliberate simplification of native's per-tab
  measured width, noted in-code so it isn't read as a bug.)
- **Stepper + slider arrows now share constant right-anchored x-columns (D).** Both the
  ON/OFF stepper arrows and the slider `[<]`/`[>]` arrows derive from native-anchored
  constants (`RA = ROW_W`; `ROW_W = list_width − 100 = 1300`): decrement (left) arrow at
  `RA−400` is a single flush column for BOTH types; increment (right) arrow at `RA−19`
  for steppers / `RA−71` for sliders (52px inboard to clear the slider's value box, per
  native); value text centered at `RA−200` (stepper) / `RA−25` (slider). The slider
  track/fill moved into the input-field column (`RA−370`, width 288, height 10) so its
  arrows bracket it exactly as native. Native click feel: stepper arrow hotspots widened
  to the native 200px (`INPUT_FIELD_WIDTH/2`). Replaces the old `TRACK_X`/`TRACK_W`
  flanking layout. (`options_view_definitions.lua` :3404-3512 stepper, :2087-2251 slider.)
- **Slider + checkbox label fonts reduced to native 16 (E).** Native slider label is 16
  (`:1991-2002`); booleans render as a stepper so they use the native stepper label 16
  (`:3488-3502`), not the native checkbox label 28. Slider was 18, checkbox was 24.

### Fixed
- **Keep ESC menu separator no longer bleeds through the lifted button text (A).** The
  `gut_compact_esc_menu` hook lifts the button column up by `TOP_BIAS`, but the keep
  `divider` widget's position was unchanged, so the raised text overlapped the stationary
  rule. The `HeroWindowIngameView._update_presentation` hook now also shifts the
  `_widgets_by_name.divider` render `offset[2]` up by the same `TOP_BIAS` (SET, not
  accumulate — idempotent across presentation rebuilds), keeping it visible above the
  menu text. (`hero_window_ingame_view_definitions.lua:279`.) *Tune-in-game: bump to
  `TOP_BIAS + SPACING` if it needs to clear the top text row.*

## 0.2.64-dev (2026-06-22) — FIX two long-standing layout bugs (title overlap + keep-menu overflow), both rediagnosed

Two fixes where prior attempts changed the wrong lever. Both are visual and need an
in-game eyeball to confirm the exact placement (per-item notes). The title fix lives
once in the shared `_mod_tweaker_definitions.lua` (so it lands in BOTH verbatim twins
automatically); the keep-menu fix is in `gui_tweaker.lua`.

### Fixed
- **Mod Tweaker title no longer renders behind the tab strip (PROBLEM 1).** Root cause
  was NOT z-order (the prior build-3 fix bumped the title's z to 20 + drew it after the
  tabs — both Z-ORDER levers, which don't separate two widgets that share the same
  screen rectangle). The real cause: `mt_title` AND the `mt_tab_*` nodes both parented to
  `background_top_panel` (the 50px top band) with `vertical_alignment = "center"`, so
  they occupied the SAME band and overlapped spatially. Fix: vertically split the band —
  the title is now TOP-aligned in the upper ~22px, the tab strip BOTTOM-aligned in the
  lower ~26px (mirrors native Options, where the tab buttons hang off the panel BOTTOM
  via `button_pivot`). Title font 28 -> 22 to fit the slimmer band. *Needs in-game
  eyeball to confirm the title clears both the tabs and the cogwheel.*
- **Keep ESC "Main Menu" no longer overflows; logo hidden (PROBLEM 2).** Root cause: the
  prior `gut_compact_esc_menu` hook (since v0.2.56) targeted `IngameView.set_background_height`,
  but the keep pause menu is the MODERN `HeroWindowIngameView` sub-window (the bare legacy
  `IngameView` is only the in-mission menu) — that class has no `set_background_height`, so
  the hook NEVER FIRED there. Its logo-hide branch was also dead even on the legacy path
  (`IngameView.create_ui_elements` never assigns `self.logo`). Now gut hooks
  `HeroWindowIngameView._update_presentation` (the method that lays out the button column
  at spacing 60 and sizes the panel — `hero_window_ingame_view.lua:490-515`): once the
  column crosses ~8 buttons it re-packs the column tighter (spacing 60 -> 48) with an
  up-bias and hides the keep logo (zeroing `style.texture_id.color` alpha — the path
  `create_simple_texture` actually uses, not `style.color`). *Column lift amount + spacing
  are tune-in-game values; needs an in-game eyeball.*

## 0.2.63-dev (2026-06-22) — Mod Tweaker refinements toward the native settings menu

Five tweaks pushing the Mod Tweaker menu closer to VT2's native Options menu. All
visual — they need an in-game eyeball to confirm the exact look (see the per-item
notes). View/draw changes landed identically in BOTH verbatim twins
(`_mod_tweaker_view.lua` + `_mod_tweaker_state.lua`); shared factory changes live
once in `_mod_tweaker_definitions.lua`.

### Changed
- **Tab label overrides (item 5).** Added a `_TAB_LABEL_OVERRIDE` map (in both twins)
  applied in `_rebuild` BEFORE the "Tweaker: " prefix-strip + truncation, so a mapped
  mod's tab reads exactly the override. `cim` + `cim_dev` -> "CRAFTING". General Tweaker
  (`gt`/`gt_dev`) is left as-is (its VMF name already reads "General"). Easy to extend
  with more `<mod_id> = "LABEL"` lines.
- **Removed Verminious Dreams Lighting from the Mod Tweaker (item 7).** Dropped
  `verminious_dreams_lighting` + `_dev` from `_MY_MODS` in both twins so they no longer
  appear as a Mod Tweaker tab. They keep their own normal VMF menu. (The separate
  `_gut_config_file.lua` TOML-export whitelist is intentionally left untouched.)
- **Brighter row hover highlight (item 9).** Raised the `_append_highlight`
  ("playerlist_hover") alpha from 70 to 255 to match native's full-alpha row hover.
  *Needs in-game eyeball.*
- **Slider arrows flank the track (item 2).** The `[<]`/`[>]` arrows now sit just left
  and just right of the slider TRACK (value text after), column-justified off the
  constant TRACK_X/TRACK_W across all slider rows — matching native order, instead of
  both arrows bunched to the far right after the value. The track drag hit-zone was
  tightened to the track bounds so it no longer overlaps the flanking arrow hotspots.
- **Tighter rows + native-er fonts (item 4).** Row height 46 -> 32 (native is 30 with
  zero inter-row gap); checkbox label font 22 -> 24, slider label font 22 -> 18 (native
  is 28 / 16, using the masked font — gut uses the unmasked font, so these are
  tune-toward values). *Exact px needs an in-game eyeball.*

## 0.2.61-dev (2026-06-22) — FIX blank Mod Tweaker (rows=0): VMF header was hiding every setting

The build-4 gear refactor of `_build_rows` treated any node whose next node is deeper
as a "gear parent" and set `skip_below` to hide its children inline. But VMF's per-mod
widget list starts with a synthesized **header** node, with every setting a deeper
sibling under it — so the header itself was treated as a gear-parent and `skip_below`
hid EVERY setting. Net: header → nil row, all settings skipped → the menu rendered only
the tab strip with a blank body (`[mt] rebuild ... rows=0` in the log).

Fix: exclude `wtype == "header"` from the `has_children` gear/skip branch in BOTH twins
(`_mod_tweaker_view.lua` + `_mod_tweaker_state.lua`). Verify in-game: the menu body shows
settings; the `[mt] rebuild` debug line reads `rows=` > 0.

## 0.2.60-dev (2026-06-22) — Mod Tweaker keep ESC button now actually opens (force_open)

### Fixed
- **"MOD TWEAKER" in the keep ESC menu darkened the screen then opened nothing.**
  The build-2 keep path fired `transition_with_fade("hero_view", { menu_state_name =
  "gut_mod_tweaker" })`, the fade played, but the `gut_mod_tweaker` HeroView sub-state
  never switched in. Root cause: the ESC "Mod Tweaker" button fires from INSIDE the
  already-open keep ESC menu, which *is* `hero_view` (the `ingame_menu` window inside
  `HeroViewStateOverview`), so `IngameUI.current_view == "hero_view"` ALREADY. When the
  transition closure set `current_view = "hero_view"` again, `IngameUI.handle_transition`'s
  re-enter guard `if old_view ~= new_view or force_open` (`ingame_ui.lua:953`) evaluated
  `"hero_view" ~= "hero_view"` (false) with no `force_open` → it SKIPPED
  `HeroView:on_enter` / `post_update_on_enter`. And `post_update_on_enter`
  (`hero_view.lua:504-508`) is the ONLY code that reads `menu_state_name` and calls
  `_change_screen_by_name`. So `menu_state_name = "gut_mod_tweaker"` was silently dropped:
  fade in, fade out, no screen change. (The `[gui_tweaker] hero_view: state=?` diagnostic
  reflected the machine still sitting on the overview state, never switched.)
  - **Fix:** pass `force_open = true` in the transition params. This is the EXACT vanilla
    keep-button flow — every keep ESC menu button (Inventory, Loot, …) uses
    `transition = "hero_view"` + `transition_state = <screen>` + `force_open = true`
    (`ingame_view_menu_layout_console.lua:742-745`). `force_open` makes the
    `handle_transition` guard pass even when `old_view == new_view == "hero_view"`, forcing
    the re-enter so `post_update_on_enter` honors `menu_state_name`. Harmless on the
    not-already-in-hero_view path (`/gut_mod_tweaker` from gameplay), where `old_view`
    is `nil` and the re-enter happens regardless.
  - Applied to all three sub-state openers so they're robust regardless of entry state:
    the ESC closure (`gui_tweaker.lua` ~910), the `/gut_mod_tweaker` chat opener
    (`mod._gut_open_mod_tweaker`, `_ba_heroview_inject.lua`), and the compendium opener
    (`mod._gut_open_compendium`, same file) — the compendium carried the identical latent
    bug, masked only because `/gut_armory` / `/gut_bestiary` are chat-only (fired with no
    menu open, where `old_view` is `nil`).
  - **No new `mod:hook`/`mod:hook_safe` registrations** (pure params change). The
    in-mission standalone `ModTweakerView` path is untouched — it still opens its own view
    and routes exit via the origin-captured `_exit_transition`.

## 0.2.59-dev (2026-06-22) — Mod Tweaker gear "Advanced Settings" drill-down + slider thumb move fix

All Mod Tweaker view changes land identically in BOTH the in-mission standalone
`ModTweakerView` (`_mod_tweaker_view.lua`) and the keep `HeroViewStateModTweaker`
sub-state (`_mod_tweaker_state.lua`) — they are verbatim twins. The shared widget
factories live once in `_mod_tweaker_definitions.lua`.

### Added
- **Gear "Advanced Settings" drill-down (issue #79).** Any setting that owns nested
  sub-options now shows a 3rd-column **gear** (cogwheel) instead of flattening its
  children inline. Clicking the gear drills INTO that setting *in place*: the same
  list converts to a `< Back` row + the parent setting's own row + one row per child,
  on the SAME scenegraph/scrollbar. The `< Back` row (or the **first ESC**) drills back
  OUT to the normal list; a second ESC closes the menu. Tab/page switching is guarded
  while drilled. Good test targets on gut's own tab: **Parry Indicator**
  (`gut_parry_indicator` + R/G/B children) and **Respawn Timer** (`gut_respawn_timer`
  + font-size/R/G/B children).
  - Detection of "has children": gut NESTED categories = a non-`group` node with a
    non-empty `sub_widgets`; VMF FLAT categories = the next node's `depth` is greater
    than this node's. The nested walk now synthesizes a parallel `depth` array
    (`_walk_nested` replacing `_walk_leaves`) so BOTH paths run the identical
    "next node is deeper" detection + inline-skip. Groups keep their existing
    `[+]/[-]` collapse (no gear); only non-group parents get a gear.
  - The gear texture is `cogwheel_small` (`gui_icons_atlas`, 40x40) — the SAME sprite
    the window chrome already draws every frame as `menu_symbol`, so it's proven to
    resolve on the borrowed renderer (no raw-material crash risk). Its hotspot carries
    an explicit `style_id` (rows share the `mt_list_start` node, so without one the hit
    target collapses to 1x1 — the same gotcha already handled for checkboxes). The
    gear-parent's whole-row hotspot is trimmed so it stops before the gear column and
    a gear click can't double-fire on the parent row.
  - Child rows reuse the existing checkbox/numeric/dropdown build + `_cat_get`/`_cat_set`
    — **no new persistence**. The per-node row build was factored into a shared
    `_build_node_row` helper so the normal list and the drill view build rows identically.
  - **No new `mod:hook`/`mod:hook_safe` registrations** (mod-lint clean: 47 hooks,
    0 duplicates).

### Fixed
- **Slider thumb / fill now actually move (the build-3 "thumb doesn't move" report).**
  Root cause found in the decompiled engine, not guessed: `offset_function` is **not**
  a generic per-pass field. The generic widget draw loop (`ui_renderer.lua:521-555`)
  places each pass from `pass_style.offset` but NEVER calls `offset_function` for
  `texture`/`rect`/`texture_uv` passes — only the dedicated **`local_offset`** pass
  type invokes it (`ui_passes.lua:4587-4593`; the native slider uses exactly this at
  `options_view_definitions.lua:1673-1695`). The prior build attached the thumb/fill/
  thumb_hover `offset_function`s to `texture`/`rect` passes, where they were silently
  ignored — so the fill stayed at width 0 and the thumb stayed pinned at value 0.
  Fixed by replacing those dead per-pass functions with a single `local_offset` pass
  that mutates `style.fill.size[1]`, `style.thumb.offset[1]`, and
  `style.thumb_hover.offset[1]` in place from `internal_value` every frame — the
  native mechanism. The `[mt:slider-probe]` debug log is preserved (now inside the
  `local_offset` pass).

## 0.2.58-dev (2026-06-22) — Mod Tweaker native-settings fidelity: ON/OFF switches, texture arrows, moving thumb, separators, hover/sounds + in-mission origin-exit fix

All Mod Tweaker view changes land identically in BOTH the in-mission standalone
`ModTweakerView` (`_mod_tweaker_view.lua`) and the keep `HeroViewStateModTweaker`
sub-state (`_mod_tweaker_state.lua`) — they are verbatim twins. The shared widget
factories live once in `_mod_tweaker_definitions.lua`.

### Fixed
- **In-mission Mod Tweaker exit now returns to the menu the player actually opened — no more deprecated bare `IngameView` after exiting in a mission.** The prior build fixed only the keep path (HeroView sub-state). In a mission the standalone view's exit was hard-coded to `"ingame_menu"` (the deprecated legacy menu), so players who opened the modern HeroView ESC menu (the PC default, `use_pc_menu_layout=false`) were dumped into the bare 9-button legacy menu on exit. The transition closure now **captures the origin view** (`self.current_view`, still the engine's pre-closure snapshot per `ingame_ui.lua:946`) and routes exit back to it: `hero_view` origin → `hero_view` (which `ModTweakerView:exit` already handles safely with `{ menu_state_name = "overview" }`), everything else → `ingame_menu`. The `mod_tweaker_transition_registered` regression check now asserts both origin branches. (Same bug class as memory `reference_vt2_modview_exit_legacy_ingameview`.)
- **"MOD TWEAKER" title no longer renders behind the tabs.** The title and the tab strip both parented to `background_top_panel` at equal world-z and the title was drawn first, so the tabs overpainted it. Fixed two ways (belt-and-suspenders): the title node's local z is bumped `{0,0,4}` → `{0,0,20}` (above the tabs at z=4), and `_draw` now draws the title **after** the tab loop. The title is text-only (no hotspot) so drawing it last can never eat a tab click.

### Changed
- **Booleans render as a native ON/OFF stepper switch instead of a hand-built checkbox.** VT2's native settings render booleans as two-option steppers (`{true → "menu_settings_on"} / {false → "menu_settings_off"}`, `options_view_settings.lua:456`), not checkboxes. The `create_checkbox` factory now draws the label (left) + centered ON/OFF text (from the game's own `menu_settings_on`/`menu_settings_off` loc keys) flanked by the two native arrow textures. Either arrow, or the whole row, toggles the value.
- **Slider/stepper inc-dec controls are now the native arrow TEXTURES, not `<` / `>` text glyphs.** Left = `settings_arrow_normal` (a `texture` pass); right = the SAME texture flipped horizontally via a `texture_uv` pass with uvs `{{1,0},{0,1}}` — exactly the native pattern (`options_view_definitions.lua:1803-1837`). Hovering an arrow swaps it to `settings_arrow_clicked`.
- **Slider thumb tracks `internal_value` and shows the atlas `slider_thumb`/`slider_thumb_hover` sprite.** The thumb's `offset_function` recomputes `offset[1] = TRACK_X + TRACK_W·internal_value − thumb_w/2` every frame (mutating the offset table in place), so the thumb visibly slides as the value changes. A debug-gated probe (`[mt:slider-probe]`, throttled ~1/sec, gated on `enable_debug_logging`) logs `internal_value`, the computed thumb `offset[1]`, and whether the `slider_thumb` texture resolved — so if the thumb still doesn't move in-game the log pins the cause.
- **Per-row separators.** Each row now draws a faint full-width 2px bottom rule (a plain `rect` pass — never the native `rect_masked` material, which is absent on the borrowed renderer), color `font_default @ alpha 50`, matching the native `bottom_edge` (`options_view_definitions.lua:25-26`). Rows stack with no gap, so the rules read as one continuous ruled list.
- **Right-justified controls / left-justified names.** Control column x is now derived as `ROW_W − INPUT_FIELD_WIDTH(400)` (the native right-justify rule) instead of the old magic `600`; the slider track width was reduced so the track + value text + both arrows fit inside the right column. Names stay flush-left.
- **Tabs are ALL-CAPS with native 20px inter-tab spacing.** The tab text style now sets `upper_case = true` (a pure render transform — `localize` stays `false` since mod names aren't loc keys), and the inter-tab gap is 20px to match native (`options_view.lua:993`).
- **Mouseover hover highlight on rows + controls.** Each editable/clickable row draws the atlas `playerlist_hover` sprite (in `gui_menus_atlas`, gated on `content.is_highlighted`) when its hotspot is hovered. Set per-frame from the row hotspot's `is_hover` in the new `_apply_row_hover` draw helper.
- **Native Wwise sounds.** `_play_click` now fires `Play_hud_select` on every commit (checkbox flip, arrow click, dropdown cycle, slider release); a new `_play_hover` fires `Play_hud_hover` on the hover-enter edge only (debounced per row, never every frame), matching the real Options menu (`options_view.lua:544`/`423`). A one-time debug-gated `[mt:wwise]` probe logs which worlds expose a usable `wwise_world` (current handle is the `music_world`'s); if `Play_hud_*` are inaudible the log shows whether the handle resolved.

All textures used are atlas-backed and proven to resolve on the borrowed renderer: `slider_thumb`/`slider_thumb_hover`/`settings_arrow_normal`/`settings_arrow_clicked` (`gui_settings_atlas`), `playerlist_hover` (`gui_menus_atlas`). No raw materials (`checkbox_checked`/`rect_masked`/`highlight_texture`) are referenced — they crash on this renderer (memory `reference_vt2_options_widgets_raw_materials`). No new `mod:hook`/`mod:hook_safe` registrations were added.

## 0.2.57-dev (2026-06-22) — Mod Tweaker as a HeroView sub-state (keep path): kills the deprecated-menu look AND the LA-atlas crash

### Fixed
- **Opening the Mod Tweaker from the keep is now a HeroView SUB-STATE — no more deprecated bare-IngameView menu on exit, and no more Loremaster's Armoury `armoury_atlas` crash on repeated opens.** Root cause of BOTH symptoms: the keep path reached the Mod Tweaker by *leaving and re-entering* `hero_view` via `transition_with_fade`, which **recreates hero_view's renderer**; VMF then re-injects LA's atlas into the fresh renderer (the C-fatal, crash `42c81d84`), and the recreation dumped the player back into the deprecated standalone `IngameView` (the bare 9-button menu). A HeroView sub-state stays **inside the already-open hero_view and never recreates the renderer**, eliminating both. This is the proper fix the prior build's TODO described (modeled on the existing `HeroViewStateCompendium` sub-state). The in-mission path is **unchanged** — there's no `hero_view` in a mission, so the ESC "Mod Tweaker" button there still opens the standalone `ModTweakerView` (which routes its own exit to `ingame_menu`, the never-crashed path), preserving in-mission access.

### Added
- **`HeroViewStateModTweaker`** (`_mod_tweaker_state.lua`) — the Mod Tweaker rendered as a hero-menu sub-state. Ports the VMF auto-discovery, General-Tweaker-first tab ordering, pagination, collapsible groups, draggable sliders/dropdowns, scroll/cull, and the pcall-protected `end_pass` draw guard verbatim from `_mod_tweaker_view.lua`; the lifecycle shell follows the sub-state contract (renderer borrowed from the hero_view context — never recreated; input read from the parent hero_view's shared service; cursor managed by hero_view — gut pushes none; exit via `parent:close_menu`). The on-exit settings auto-save (TOML export) is preserved. Reachable in the keep via the ESC "Mod Tweaker" button **or** the new `/gut_mod_tweaker` chat command.
- **`/gut_mod_tweaker`** chat command — opens the Mod Tweaker hero-menu sub-state from the keep (mirrors `/gut_armory`); echoes a hint if used outside the keep.

### Changed
- The `gut_mod_tweaker` screen descriptor is registered alongside `gut_compendium` in the **single existing** `HeroView.init` hook (no new duplicate hook). The ESC "Mod Tweaker" transition closure now branches on `ingame_ui_context.is_in_inn`: keep → sub-state, mission → standalone view.

## 0.2.56-dev (2026-06-22) — ESC-menu overflow fix, pin General Tweaker tab, LA-atlas re-pin + instrument

### Fixed
- **ESC/keep menu no longer overflows off the bottom of the screen.** gut injects a "Mod Tweaker" button into the IngameView button column; on the keep host/client layout this makes 9 buttons, and the vertically-centred column ran off the bottom edge. A new `hook_safe("IngameView", "set_background_height", ...)` nudges the column up (and dims the logo/top panel) once the column crosses 8 buttons. Gated behind a new **Compact ESC Menu** checkbox (`gut_compact_esc_menu`, default ON). *NOTE: the nudge direction (up vs down) and the 44px/row amount are tune-in-game values — the column may move the wrong way on this first build; flip the sign after the user reports what they see.*
- **In-mission "Mod Tweaker" crash on the 3rd/4th open (materials/Loremasters-Armoury/armoury_atlas) — stopgap + instrumentation.** Root cause: the Mod Tweaker BORROWS the long-lived IngameUI renderer (it does NOT recreate it), but `_la_atlas_keepalive.lua` only pinned LA's atlas package ONCE (on `StateInGameRunning.on_enter`) — its premise that LA always keeps the atlas resident is false, so the atlas can be unloaded between opens and the borrowed renderer then hands a missing material to a C-fatal. gut now **defensively re-pins LA's package on every Mod Tweaker open** (both the ESC transition and `ModTweakerView:on_enter`), pcall-guarded and keeping the keepalive's `has_loaded` guard intact (it still NEVER force-loads a non-resident LA package — that was the 0.2.54 crash). Added debug-gated instrumentation: atlas residency, gut's pin state, an open-counter (1st/2nd/3rd/4th), the borrowed `ui_renderer`/`ui_top_renderer` identity per open, and a read-only log-and-passthrough hook on `PackageManager.unload` filtered to LA's package to catch any unload between opens. All instrumentation is gated on `enable_debug_logging`.

### Changed
- **General Tweaker is now pinned as the first (leftmost) Mod Tweaker tab.** The per-mod tab strip puts `gt` (stable) / `gt_dev` (dev) first regardless of the default ordering; every other mod keeps its existing relative order. Implemented via an explicit `TAB_PRIORITY` list so it's easy to extend later.

## 0.2.55-dev (2026-06-22) — NumericUI ability cooldown shows real-time reduced seconds

### Added
- **NumericUI's ability-cooldown number now counts in real seconds.** VT2 applies cooldown reduction by making the cooldown value *decrease faster* (`career_extension.lua:244`: `reduce_activated_ability_cooldown(dt * cooldown_regen_mult)`), not by shortening it — so NumericUI's display, which shows the raw `current_ability_cooldown()`, visibly **sped up** under CDR. gut now divides that read by the same `cooldown_regen` multiplier **only while NumericUI is computing its display** (inside its `UnitFramesHandler._sync_player_stats` hook), so the number shows the accurate reduced cooldown ticking at 1 second per second. The game's actual cooldown logic, the ability-bar fill, and bot AI are untouched (the flag can't leak — vanilla `_sync_player_stats` never reads the cooldown seconds). No-op if NumericUI isn't installed.

## 0.2.54-dev (2026-06-21) — Fix: the LA atlas keepalive itself hard-crashed (force-materialized LA's broken bundle)

The v0.2.53 keepalive (`_la_atlas_keepalive.lua`) called `Managers.package:load(LA_PACKAGE, GUT_REF, nil, true)` on every `StateInGameRunning.on_enter`. The 4th arg is `asynchronous` (not "persistent", as the comment wrongly claimed) — and because LA dynamically **unloads its own package**, at our on_enter the package is often NOT resident, so `load()` QUEUED a fresh load that **force-materializes every member of LA's bundle**. LA's installed bundle is missing an internal member, so the async `_pop_queue → resource_package` step took a C-level fatal: `Resource '#ID[3ac73385950a26ea]' not found` (that hash IS this LA package — Stingray names bundles by murmur64A of the package path). The `pcall` couldn't catch it (the fatal fires async, outside the Lua frame). Recurred every keep entry while LA was installed; vanilla was unaffected.

### Fixed
- `_la_atlas_keepalive.lua` now **only pins when LA's package is ALREADY fully resident** (`pm:has_loaded(LA_PACKAGE)`), making `load()` a pure reference-count increment — no re-materialize, no fresh-load queue. If LA's package isn't resident at on_enter (LA unloaded it / not loaded yet), it bails and retries next entry instead of force-loading it. The reference (held by `GUT_REF`) still survives LA's own unload, so the atlas stays resident when we do pin. Corrected the misleading "4th arg = persistent" comment. MOD_VERSION → 0.2.54-dev.

## 0.2.53-dev (2026-06-21) — Guard the Loremaster's Armoury atlas crash on the hero view

### Fixed
- **`[Script Error]: materials/Loremasters-Armoury/armoury_atlas` opening the hero menu (crash efadf778).** Root cause (traced from the full stack): LA registers its atlas for VMF custom-texture injection into the `hero_view` renderer-creator; the hero view's HDR sub-renderer (`hero_view_hdr`) shares that creator, so VMF injects the atlas there during `_setup_hdr_renderer`. LA *also* dynamically unloads its own package (it hooks `PackageManager.unload`), so the atlas is sometimes gone when that early HDR renderer is built → `create_screen_gui` C-fatal (not catchable by the `pcall` cim wraps around `_setup_hdr_gui`). Not a gut bug — gut wasn't in the stack — but fixable from our side: gut now **pins LA's package under its own package-manager reference** (on `StateInGameRunning.on_enter`) so LA's unload can't drop the atlas out from under the renderer. No-op if LA isn't installed. (Fix authorized by LA's authors; shipped in gut per the constraint that it ship from our mods.)

## 0.2.52-dev (2026-06-21) — Stop messing with captions at default settings

### Fixed
- **Captions/subtitles were being repositioned even with no settings changed.** The `SubtitleGui.update` hook (from the absorbed HideBuffs "reposition subtitles" feature) ran every frame as a `hook_safe` and unconditionally wrote `subtitle_widget.offset = {x, y}` — and since the subtitle-offset settings aren't exposed in gut's UI, `x`/`y` were always `0`, so it clobbered vanilla's own caption positioning with `{0, 0}`. Now it bails when both offsets are 0 (the default), leaving vanilla positioning untouched; it only moves captions if a non-zero offset is actually set.

## 0.2.51-dev (2026-06-21) — `<>` on the ESC entry: actual root cause fixed + tracked status doc

### Fixed
- **The `<>` on the "Mod Tweaker" ESC entry — finally root-caused.** The modern hero menu (`hero_window_ingame_view.lua:473`) builds the label as `text_field = display_name_func() or display_name` and then **localizes** `text_field`. Our button carried a `display_name_func` that returned the already-resolved string `"Mod Tweaker"`, so the menu re-localized that literal into **`<Mod Tweaker>`**. The legacy ESC menu used the key directly (which is why the probe always showed it resolving), masking the real culprit. Removed the func — the `display_name` key now localizes to "Mod Tweaker" (via the append fix) in **both** menus.

### Process
- Added **`GUI_TWEAKER_TODO.md`** — a tracked, honest status list of every Mod Tweaker / GUI request (active bugs, the native-parity rework phases, and what's done) so nothing gets dropped. The deprecated-menu-on-exit fix (make the Mod Tweaker a HeroView sub-state) and the native-parity rework are logged there as the next big tasks.

## 0.2.50-dev (2026-06-21) — Temporal Fix: baked in at -48, always on (no toggle/slider)

### Changed
- **UI Tweaks "Temporal Fix" is now always on with a baked-in `-48` nudge** (the value that lands the mini-HUD player health bar correctly). Removed the `gut_uitweaks_temporal_fix` checkbox and the `gut_temporal_hp_nudge_x` slider — the fix just applies whenever UI Tweaks (HideBuffs) is installed with its mini-HUD layout. (`gut_buffbar_endtime_fix` stays as a toggle.)

### Notes from the latest log
- The ESC-menu **`<>` is resolved** — the probe confirms `Localize('mod_tweaker_button_name') -> 'Mod Tweaker'`. If any `<>` remains it's a different element inside the Mod Tweaker view, not this button.
- Scrollbar `thumb_frac` computes correctly (0.936, scaling to content); no drag was exercised in the log, so slider/scrollbar dragging still needs an in-game check.

## 0.2.49-dev (2026-06-20) — Hide UI: fold in the proven original mod's outline + arms hiding

Compared the migrated feature against the **original "Hide UI" mod** (Workshop 2007374303) it replaces, and added the two pieces it was missing — all APIs re-verified against the current engine:
- **Outline system disabled** in complete/camera modes (`outline_system:set_disabled(true)`), so enemy/ally silhouettes hide too. Re-enable is **guarded against the Realism mutator** (which manages outlines itself), exactly like the original.
- **First-person arms hide** now uses the proper `first_person_extension:hide_weapons()` + the `first_person_attachment_unit` toggle (what vanilla `set_first_person_mode` does) instead of brute-forcing the whole FP rig — more correct, with the per-slot loop kept as a fallback.
- Outline/arms state toggles only on mode transitions (not every frame), and resets out of mission so re-entering a level re-applies against the fresh OutlineSystem/FP rig.

## 0.2.48-dev (2026-06-20) — Hide UI feature (migrated from gt, fixed) + exit-crash revert

### Added
- **Hide UI** (off / partial / complete / camera), migrated from General Tweaker. A dropdown + a cycle hotkey (`/gut_hud`). Two bugs that made it a no-op in gt were fixed in the move: the HUD-disable hook now targets the **derived** game-mode classes (the base-class hook never fired because VT2 copies methods into subclasses at definition time), and the force-hide path now reads `Managers.ui._ingame_ui.ingame_hud` (the old `Managers.ui.ingame_hud` was nil).

### Fixed / reverted
- **Mod Tweaker exit no longer crashes with Loremaster's Armoury.** v0.2.46 returned to `hero_view` on exit, but recreating hero_view makes VMF re-inject every mod's custom UI material into the new renderer, which hard-crashed on `materials/Loremasters-Armoury/armoury_atlas` (crash 42c81d84). Reverted to the `ingame_menu` exit (no crash; the older menu style returns). The proper fix — making the Mod Tweaker a HeroView **sub-state** so it never recreates hero_view (kills both the crash AND the legacy look) — is noted in code as the next step.

### Diagnostics
- The backend-loc registration now also logs `Localize('mod_tweaker_button_name')` right after registering, to confirm whether the `<>` you still see is this ESC button (would print `<...>`) or a different element (would print `Mod Tweaker`).

## 0.2.47-dev (2026-06-20) — Fix hero-menu crash on exit (v0.2.46 regression)

### Fixed
- **Crash exiting the Mod Tweaker:** `hero_view_state_overview.lua:73: attempt to index field 'state_params' (a nil value)`. v0.2.46's deprecated-menu fix routed the exit to `transition_with_fade("hero_view")` with **no params** — HeroView's `post_update_on_enter` then took its else-branch (`_change_screen_by_index(1)`), which enters the overview state with `state_params = nil`, and the vanilla overview indexes `params.state_params.force_ingame_menu` with no nil guard → crash. Now the exit passes `{ menu_state_name = "overview" }` so HeroView threads our (table) params through as `state_params` — the same pattern the compendium open already uses. The deprecated-menu fix stays intact; it just returns cleanly now.

## 0.2.46-dev (2026-06-20) — Deprecated-menu ROOT CAUSE fix + GUI probes (Phase 0 of native-parity rework)

A second multi-agent investigation found the *real* deprecated-menu cause (renderer/layout-variant theories were both wrong) and produced a full phased plan to make the menu match native settings.

### Fixed
- **"Deprecated menu after exiting" — actual root cause.** The Mod Tweaker is opened from HeroView's modern embedded menu, but its exit **hardcoded `transition_with_fade("ingame_menu")`**, which opens the standalone **legacy `IngameView`** (the bare 9-button menu). So exiting ejected you from HeroView into the old menu. Now the transition closure captures the **origin view** (`self.current_view`) and routes the exit back there (`hero_view` → returns to the modern menu). `on_enter` preserves that origin instead of clobbering it. (The `[mt:esc]` diagnostic exposing the 10-vs-9-button alternation is what cracked this.)

### Added (probes)
- `[mt:slider] DRAG …` logs `internal_value` + computed thumb x every drag frame — to prove whether the drag math works (it does) vs the thumb-render/reference-frame is the defect (the shared-node root cause).
- `[mt:dump] heartbeat …` now logs `thumb_frac` + `scroll_value` — to show why the scrollbar thumb stays full-size.
- `[mt:esc] opened from current_view=… -> exit will route to …` confirms the origin-capture fix.

### Roadmap (native-parity rework, next)
Per the investigation: keep custom widgets (native factories crash on the borrowed renderer), but give **each row its own scenegraph node** (the shared `{1,1}` node is the root cause of the dead slider drag + cosmetic scrollbar), then port native hover/sound/tooltip/drag. Phases: 1) per-row nodes, 2) slider+scrollbar drag, 3) dividers/two-column/font+colors/tab-shift/nested-indent, 4) hover+sound, 5) On/Off switch + type-in number + tooltips.

## 0.2.45-dev (2026-06-21) — `<>` button: fix registration TIMING

The v0.2.44 `append_backend_localizations` approach was right, but `Managers.localizer` wasn't ready at gut's boot, so it silently no-op'd (the log shows no registration line). Now it also registers on `on_all_mods_loaded`, on `LocalizationManager.init`, and on **`IngameView.on_enter`** (fires right before the ESC menu draws, localizer guaranteed up) — so the key is set before the button's text resolves. The register helper now logs at info level so the next log confirms it fired.

Note: the "deprecated menu after exit" is being re-investigated — the `[mt:esc]` diagnostic revealed it's the **legacy button-layout variant** (9-button `*_legacy` set), not a renderer issue, so v0.2.44's renderer switch was the wrong fix. A larger native-menu rework (font/colors, On/Off toggles, hover+sound, tooltips, dividers, functional scrollbar, nested indentation) is being designed.

## 0.2.44-dev (2026-06-20) — Root-cause fixes for the `<>` button + deprecated-menu (multi-agent investigation)

A fan-out investigation finally found both root causes (prior fixes had attacked the wrong layer).

### Fixed
- **`<mod_tweaker_button_name>` ESC button.** Root cause: the engine's `LocalizationManager._base_lookup` only checks `_backend_localizations` + compiled string bundles — **never** a mod's VMF loc table. Both prior fixes were *interception* hooks and each missed a path (the `_G.Localize` hook gets blown away by the `rawset` re-init; the `lookup` hook is bypassed because the button text pass also localizes via the **sibling** `simple_lookup`). The fix **supplies the string** instead of intercepting: `Managers.localizer:append_backend_localizations({ mod_tweaker_button_name = "Mod Tweaker" })`, which `_base_lookup` checks first — so it resolves on *every* path. Re-registered on `LocalizationManager.init` (language switch). Deleted both failed hooks.
- **ESC menu "deprecated buttons" after exiting.** Root cause: the Mod Tweaker drew on `ui_renderer` (level_world / in-mission HUD renderer) — the **only** ESC-flow view to do so. OptionsView and IngameView both draw on `ui_top_renderer`; gut polluting level_world's renderer state made IngameView's chrome fail to resolve on the next frame → flat buttons. (My v0.2.40 comment claiming IngameView shares `ui_renderer` was factually wrong — it's on `ui_top_renderer`.) Fix: draw on `ui_top_renderer` like the vanilla views. Our rows are already atlas-safe, so the original reason for level_world no longer applies.

## 0.2.43-dev (2026-06-20) — Collapsible groups

### Added
- **Group headers are now collapsible** (interim organization until a better sort lands). Each VMF `group` becomes a clickable header with a `[+]`/`[-]` indicator on a tinted bar; clicking it expands/collapses its settings. Uses each flat node's `depth` to skip a collapsed group's descendants (handles nested groups). **Groups start collapsed**, so opening a big mod (e.g. ct's ~1900 settings) shows a tidy list of group headers instead of an endless flat scroll — expand only what you need. Expand state persists across tab switches for the session.

## 0.2.42-dev (2026-06-20) — Slider matches VMF (mod-side snapping) + two-column layout

### Fixed
- **Slider now lands on the same values as VMF.** Found it: `starting_coins` is `range = {0, 3000}` and its **own `on_setting_changed` snaps the value to the nearest 25** (not a VMF slider step). VMF shows the snapped value because it re-reads after setting; my menu showed the raw drag value (257 vs 250). Now after a commit the menu **re-reads the stored value** and shows that — so it snaps to 25s exactly like VMF, for any mod that clamps/snaps in its change handler. Reverted the stepper to the coarser ~range/40 (the natural increment min), and added a `[mt:num] '<id>' bounds=… step=…` diagnostic (debug on) to confirm the read bounds.

### Added
- **Two-column layout** like the game's settings menu: the setting **name fills the left column**, and every **control** (checkbox box, slider track, `[<]`/`[>]` steppers) sits in the **right column** at a consistent x. Much cleaner than the old left-packed rows.

## 0.2.41-dev (2026-06-20) — Slider crash fix (per-frame commit) + finer steps

Crash dragging the Chaos Wastes `starting_coins` slider, diagnosed from the log.

### Fixed
- **Crash + "slider didn't move" while dragging.** The drag committed the value via `mod:set(..., true)` **every frame**, firing the mod's `on_setting_changed` continuously. For `starting_coins`, that handler **broadcasts the entire ~18KB config to clients** (`[ct_sync] ... 18133 bytes, 489 keys`) — once per frame floods the network and crashes (and the crash interrupted the visual, so the bar looked frozen). Now the drag updates only the **visual** each frame and **commits once on release** (matching how VMF fires a setting change). Smooth drag, one network sync, no crash.
- **Stepper increments were too coarse (≈25/click).** The `[<]`/`[>]` step was `(max-min)/40` — ~25 on a 0–1000 range. Changed to the **natural increment** (1 for integers, `10^-decimals` otherwise), matching VMF. The draggable track still handles big moves, so fine ±1 stepping no longer means tiny drags.

## 0.2.40-dev (2026-06-20) — The two stubborn ones: `<>` ESC button + "deprecated menu" after exit

Fresh diagnosis after the previous fixes didn't take.

### Fixed
- **`<mod_tweaker_button_name>` ESC button.** The log confirmed gut's `_G.Localize` hook IS registered, yet the key didn't resolve — meaning the wrapper was bypassed (the localizer re-inits via `rawset(_G,"Localize",...)`, which can blow the wrapper away). The robust fix: also hook the **`LocalizationManager.lookup` class method** — the global `Localize` is literally `function(id) return Managers.localizer:lookup(id) end`, so the method hook intercepts every localization regardless of the `_G` wrapper's state, and survives re-inits.
- **"Main menu looks deprecated (just buttons)" after leaving the Mod Tweaker.** Ruled out the exit transition (it's identical to OptionsView's). Real cause is renderer state: the Mod Tweaker draws on `ui_renderer` (level_world) — the **same renderer IngameView draws its styled background on** (its buttons are on `ui_top_renderer`). If any `draw_widget` errored between the Mod Tweaker's `begin_pass` and `end_pass`, `end_pass` was skipped → the renderer was left mid-pass → IngameView's background didn't render → just bare buttons. Wrapped the entire draw body in a guard so **`end_pass` always runs** even if a widget draw throws.
- Added a `[mt:esc] setup_button_layout -> N buttons` diagnostic (debug on) to confirm the button set isn't accumulating, in case the menu look is still off.

## 0.2.39-dev (2026-06-20) — Mod Tweaker sliders are now draggable

The log confirmed checkboxes/tabs work but sliders never registered a change. Root cause: the numeric rows were a tiny `[<] value [>]` stepper — the track itself had **no hotspot**, so dragging the bar (the natural slider gesture) did nothing; only the small glyphs were clickable.

### Fixed
- **Added a draggable track hotspot** across the slider bar. Click or drag anywhere on the track to set the value from the cursor position; the `[<]`/`[>]` glyphs remain for fine ±step. Per-frame writes during a drag are skipped unless the value actually moves.

### Still queued
- **Armory/Bestiary top-tab button** in the hero menu (next to Equipment/Talents/Crafting/Cosmetics) — Phase 1, the crash-sensitive `HeroWindowOptions` injection, getting its own careful pass. Phase 0 (the `/gut_armory` stub panel) is live.

## 0.2.38-dev (2026-06-20) — Armory/Bestiary Compendium: Phase 0 (hero-menu entry + stub panel)

First slice of the Armory + Bestiary "Compendium" as a real HeroView screen (the hero menu), built on the proven old-Armory-mod injection. Phase 0 proves the injection works before the real UI lands.

### Added
- `_ba_compendium_state.lua` — `HeroViewStateCompendium`, a HeroView sub-state that draws a framed stub panel ("Compendium — work in progress") + a Back button. Defensive lifecycle (nil-guarded draw/update/input). Atlas-safe widgets only; hotspot carries `style_id`.
- `_ba_heroview_inject.lua` — registers the sub-state into `HeroView._state_machine_params.settings_by_screen` (post `HeroView.init`, idempotent), captures `ingame_ui_context` (via a self-disabling `StateInGameRunning.update` hook), and exposes `mod._gut_open_compendium(mode)`.
- `/gut_armory` and `/gut_bestiary` now **open the stub panel** in the hero menu (was: echo stub).

### Notes
- Entry point for Phase 0 is the chat commands; the **top-tab button** in the hero menu (next to Inventory/Cosmetics/Talents/Crafting) is Phase 1 (kept off the crash-sensitive tab-bar hooks until the panel is proven).
- No duplicate hooks: `HeroView.init` (distinct from gut's existing `HeroView.on_enter`) + `StateInGameRunning.update` (unused elsewhere).
- Phase plan: 0 entry+stub → 1 framed panel + Weapons|Enemies toggle + top-tab button → 2 lists from the `_ba_` data layer → 3 3D preview → 4 polish/console.

## 0.2.37-dev (2026-06-20) — Config file gets a WRITE path (log→watcher bridge) + auto-save

Answering "can't we add something that lets us write?": yes. The mod can't `io.open("w")`, but it *can* write to the log, and a desktop process can turn that into a real file write. So the game now has effective two-way file sync.

### Added
- **`tools/gut-settings-watch.ps1`** — a background watcher. Leave it running while you play; it polls the newest console log and **auto-writes `gut_mod_settings.toml`** whenever the mod emits a fresh `[gut:toml]` block (only when content changes; backs up the previous file).
- **Auto-export on Mod Tweaker close** — if you changed any setting while the Mod Tweaker was open, closing it emits the TOML to the log (so the watcher commits it). No command needed. Manual `/gut_export_settings` still works.

### Flow
Run the watcher once → adjust settings in the Mod Tweaker → close it → `gut_mod_settings.toml` is written automatically → edit it by hand any time → restart or `/gut_reload_config` to load it back. The mod still **reads** the file directly on load (v0.2.36); the watcher only provides the **write** half.

## 0.2.36-dev (2026-06-20) — External config file: edit a .toml, override VMF settings on load

New feature (queued request). Keep all your tweaker mods' settings in a `.toml` you can edit directly; on game load those values override the in-game VMF options.

### How it works (and the sandbox constraint)
VMF mods can **read** files but **cannot write** them (Stingray sandbox), so it's split:
- **Override on load** — on `on_all_mods_loaded`, gut reads `%APPDATA%\Fatshark\Vermintide 2\gut_mod_settings.toml` and `mod:set`s each value for your mods (`_MY_MODS` whitelist), so the file wins over what each mod restored. No-op if the file doesn't exist. Toggle: **Override settings from config file** (on by default).
- **Edit directly** — edit the `.toml` by hand; `/gut_reload_config` re-applies it with no restart.
- **Export** — `/gut_export_settings` dumps current settings as TOML to the log (prefix `[gut:toml]`); the companion **`tools/gut-settings.ps1`** parses the newest log and writes the `.toml` (the mod can't write it itself).

### Added
- `_gut_config_file.lua` — minimal TOML reader/writer (flat `[mod_id]` sections, bool/int/float/string; keybinds skipped), `_collect`/`apply`, `/gut_export_settings`, `/gut_reload_config`.
- `tools/gut-settings.ps1` — writes `gut_mod_settings.toml` from a `/gut_export_settings` log dump (backs up any existing file).
- Setting `gut_config_override` (default on).

### Round-trip
in-game `/gut_export_settings` → desktop `.\gut-settings.ps1` → edit the `.toml` → restart or `/gut_reload_config`.

## 0.2.35-dev (2026-06-20) — Mod Tweaker: row clicks + scrollbar drag actually fire

The v0.2.34 `style_id` fix made rows receive cursor input (hover works), but the log showed `on_release` never fired for any row (count=0) while tabs clicked fine.

### Fixed
- **Row clicks now register.** Root cause: the option rows all share the `mt_list_start` scenegraph node, and the hotspot pass's `input_pressed` state machine (ui_passes.lua:4364) doesn't persist correctly across the shared node, so `on_release` never fires. Switched the checkbox/stepper handlers to **`on_left_release`** (set on release-over-widget regardless of `input_pressed`), which tabs don't need because they each have their own node.
- **Scrollbar drag.** Now driven by the hotspot's **`is_held`** flag (set while the LMB is held over the scrollbar's own node) instead of fragile `on_pressed` + `left_hold` tracking.

### Added
- Heartbeat now logs `scroll`, `vis_h`, `cont_h`, `sb_world`, `sb_hover/held` (debug logging on) to confirm the scrollbar's position + input next session.

## 0.2.34-dev (2026-06-20) — Mod Tweaker: options are now CLICKABLE + scrollbar on-panel + tighter fit

Three fixes from the v0.2.33 in-game report, diagnosed off the auto-dump.

### Fixed
- **Couldn't change any option** — the row hotspot passes had **no `style_id`**, so the hotspot pass fell back to the scenegraph node size. Every row shares `mt_list_start` (size `{1,1}`), making each click target **1×1 pixel**. (Tabs worked because each `mt_tab_N` node has a real size.) Added `style_id = "hotspot"` to the checkbox and `style_id = "dec"/"inc"` to the slider/dropdown steppers, so they use the real `{ROW_W, ROW_H}` hit area. Checkboxes/steppers/dropdowns are now clickable.
- **Scrollbar wasn't visible** — it was right-aligned in `list_mask`, whose right edge extends ~18px **past the decorated panel**, so the bar drew off the panel. Inset it 30px (and bumped its z) so it sits inside the window. Confirmed from the dump: `list_mask` world right edge 1678 vs panel edge ~1660.
- **Options didn't fit the window** — rows were drawn if their lower OR top edge was inside the mask, so edge rows overdrew past the panel (no GPU clip). Now a row draws only when its **centre** is inside the mask — clean top/bottom boundary.

### Added
- `[mt:dbg] row input: hover/release/visible` diagnostic (debug logging on) to confirm row hotspots receive cursor input.

## 0.2.33-dev (2026-06-19) — Mod Tweaker: real scrolling (no more overflow)

Implemented from a study of the vanilla `OptionsView` scroll machinery (the working reference).

### Added
- **The option list now scrolls like the native settings menu.** Mechanism mirrors `OptionsView`:
  - **Scroll offset** applied to the `mt_list` scenegraph node (one write moves the whole row stack), same sign as `OptionsView.update_scrollbar`.
  - **Position-culling** against the `list_mask` box via `math.point_is_inside_2d_box` (lower/middle/top points) — rows outside the panel aren't drawn, so **nothing overflows** anymore. Removed the old 50-row cap.
  - **A rect-based scrollbar** (`mt_scrollbar` node + `build_scrollbar_rect`) with a thumb sized to visible/total and positioned by scroll fraction. Pure `rect`/`hotspot` passes — no `mask_rect`/`rounded_background` materials, so no raw-material crash on the borrowed renderer.
  - **Mouse-wheel** scroll (1 notch ≈ 1 row) + **thumb drag**.
  - Culled rows are non-interactive (visibility-gated clicks + cleared stale flags); scroll resets to top on tab switch.

### Notes / may need a tweak after testing
- The wheel reads `scroll_axis` off the menu input service; if that action isn't mapped there, the **thumb drag still works** and I'll add a `scroll`-pass catcher. The drag sign (`sb_pos - cursor`) may need one flip — tell me if dragging feels inverted.

## 0.2.32-dev (2026-06-19) — Fix the `<>` ESC button (table-form Localize hook) + auto-dumping probe

### Fixed
- **The ESC-menu "Mod Tweaker" button rendered as `<mod_tweaker_button_name>`.** gut's `_G.Localize` hook used the STRING form `mod:hook("_G", ...)`, which resolves the class via `_G["_G"]` — not reliably set in Stingray, so the hook silently never applied. Switched to the documented TABLE form `mod:hook(_G, "Localize", ...)`. The button now reads "Mod Tweaker". (Recorded in the localization rules.)

### Changed
- **The OptionsView probe now auto-dumps** the moment you open ESC → Options (once per game session) — no `/gut_dump_options` typing needed. Matches the data-harness philosophy: visit the menu, the layout appears in the log. The command is kept only as a manual re-dump.

## 0.2.31-dev (2026-06-19) — Add OptionsView layout probe (scrollbar groundwork)

Before implementing the Mod Tweaker scrollbar, capture how the real settings menu actually scrolls.

### Added
- `_gut_options_probe.lua` — hooks `OptionsView.on_enter` to capture the live vanilla settings-menu instance, and a `/gut_dump_options` command that dumps its scroll/mask/scrollbar machinery (the `list_mask` node bounds, `scroll_value`, `selected_settings_list` scroll fields, the `scrollbar` widget's passes/content/style, sample list-widget offsets) to the log. Ground-truth for replicating native scrolling in the Mod Tweaker. Open ESC → Options, then run `/gut_dump_options`.

## 0.2.30-dev (2026-06-19) — Temporal Fix: rebase the health-bar position + widen the nudge range

User feedback: the health-bar nudge maxed at -400 wasn't enough, and the correction was in the wrong direction.

### Changed
- **Rebased the player health-bar horizontal position** in `_gut_uitweaks_temporal_fix.lua` from Isaakk's rightward `+size/2 + 50` (the "wrong direction") to **centred on the anchor (`-size/2`) + a symmetric nudge** — negative pulls left, positive pushes right, default 0 = centred. Applies to all three bars (total_health_bar, hp_bar, hp_bar_highlight).
- **Widened `gut_temporal_hp_nudge_x` range** from ±400 to **±2000** so the bar can be placed anywhere on screen.
- **Action needed:** saved nudge values from before this build were relative to the old base — **reset the Health-bar nudge to 0 and re-dial.** (No auto-reset: VMF's settings restore could clobber it, so it's a manual one-time step.) Once you find the value that looks right, tell me and I'll bake it as the default.

## 0.2.29-dev (2026-06-19) — Mod Tweaker: fix the menu-corruption + `<MOD TWEAKER>` title + tab prefix + click sound

### Fixed
- **Menu corruption (the "deprecated buttons" look on the real menus after leaving the Mod Tweaker).** Root cause found: the Mod Tweaker **shallow-cloned** `options_view_definitions.scenegraph_definition`, sharing the node TABLES with the real OptionsView, and parented our `mt_*` nodes onto OVD nodes — so `init_scenegraph` attached our children onto the SHARED OptionsView parent nodes, corrupting it. Now a **deep copy** — every node independent, OVD untouched. (This is the real cause of the recurring "old GUI"/"`<>`" after the menu, separate from the earlier crash.)
- **`<MOD TWEAKER>` title.** `UIWidgets.create_simple_text` localizes its text even with `localize=false` passed, so the title rendered as the missing-key marker. Rebuilt title + hint as hand-made text widgets with `localize=false` (same fix as the tabs). Documented in the new localization rules.
- **Tab labels: dropped the "Tweaker: " prefix** (this menu is all your tweaker mods) — tabs now read "GUI", "Chaos Wastes", etc.
- **Click sound feedback** — tabs, checkboxes, steppers, dropdowns, and the exit button now play the native UI click sound (`play_gui_start_menu_button_click` via the music_world's wwise_world).

### Still to do
- **Scroll bar** — long mod option-lists still overflow the panel (rows are capped at 50 but not clipped/scrolled). A real scrollbar needs masked-clip rendering like the native settings list; that's the next focused task.

## 0.2.28-dev (2026-06-19) — Mod Tweaker: your mods only, fix `<TWEAKER>` tabs, cap huge trees

Addressing in-game feedback on the Mod Tweaker.

### Fixed / changed
- **Your mods only.** The menu was enumerating all ~19 installed VMF mods (no room for that many tabs). Now whitelisted to this author's mods (`_MY_MODS` in `_mod_tweaker_view.lua`): gut, wt, ct(+dev), gt(+dev), cim(+dev), crt, cosmetics_tweaker, dcp, enemy_tweaker, cwv, event_tweaker, mp, bt, vdl(+dev). Far fewer tabs.
- **`<TWEAKER>` tabs fixed.** Tabs were built with `UIWidgets.create_text_button`, which hard-codes `localize = true` + `upper_case = true` on its text — so a mod name (a plain string, not a loc key) rendered as the missing-key marker `<TWEAKER: GUI>`. Rebuilt tabs as a hand-made hotspot+text widget with `localize = false`, so the raw label always shows. Selected/hovered tab is gold, others dim grey.
- **Huge mods no longer explode.** A big mod's flattened settings tree hit `rows=1927`; with no scrolling yet that's a perf/offscreen blowup. Capped at 50 rows per category (revisit when list scrolling lands).

### Still to do (separate)
- The "options are read-only/greyed" report: most was read-only widget *types* (keybinds/groups) in non-your mods; with the whitelist you'll land on your mods' real checkboxes/sliders, which are editable. If a checkbox/slider still won't change, turn on Debug Logging, click one, and send the log (it prints `[mt:dump] input: checkbox …`).
- Armory/Bestiary will move to **HeroView tabs** (inventory/cosmetic menus), not this settings menu.

## 0.2.27-dev (2026-06-19) — Fix Phase-1 fork crash on nil offset settings (boss HP / GK quests / subtitles / twitch)

`hb/hide_elements.lua:161: attempt to perform arithmetic on a nil value` — the Phase-1 fork brought over four hooks (boss HP bar, Grail-Knight quests, subtitles, twitch vote) that also **reposition** their elements, reading 9 numeric `OTHER_ELEMENTS_*` / `GK_QUESTS_*` offset/alpha settings. Those belong to a later phase and weren't registered yet (and 6 of them weren't even in the forked `SETTING_NAMES`), so `mod:get` returned nil and the `+` crashed.

### Fixed
- Guarded all 9 reads in `hide_elements.lua` with defaults (offsets → 0, GK-quests alpha → 200, matching the hook's own default check). The hides work; the repositions are no-ops until their settings land in a later phase. No crash regardless of registration state.
- This very likely also resolves the earlier **"main menu shows old GUI + options in `<>`" after leaving the Mod Tweaker**: the `ChallengeTrackerUI._draw` (GK quests) hook reads those same nil settings and that UI draws in the keep, so it was erroring every frame and cascading into broken menu/loc rendering. With the reads guarded it no longer throws. (Please confirm next session.)

## 0.2.26-dev (2026-06-19) — Respawn countdown over a dead teammate's portrait (optional)

New optional HUD widget: a large number (seconds till respawn, one decimal) drawn over a **dead teammate's** portrait while they wait to respawn.

### Added
- `_gut_respawn_timer.lua` — hooks `UnitFrameUI.draw` (post; gut doesn't hook it, no collision), teammate frames only (`_frame_type == "team"`). Detects the dead-skull state via the frame's `data.is_dead` (set by UnitFramesHandler from the networked, husk-safe status extension) and draws the number centered on the frame's `portrait_pivot` node, with a shadow.
- **Countdown source:** VT2 Adventure has no client-synced respawn countdown (`respawn_handler`'s `game_mode_data.respawn_timer` is host-only / non-networked), so this anchors a client-side estimate to the moment `data.is_dead` flips true (= when the skull appears = when the server starts the timer) and ticks down `RESPAWN_TIME` (30) or the mechanism's `hero_respawn_time`. Reads a touch early only if the host has a `faster_respawn` buff (invisible to clients); clamped at 0; stops when assisted-respawn begins.
- Settings (group **Respawn Timer over Portrait**, default **off**): `gut_respawn_timer` toggle + `gut_respawn_font_size` (12–80, default 32) + `gut_respawn_r/g/b` colour (default 255/60/60, red).

### To verify
- Have a teammate (or bot) die and wait for respawn — a red countdown should appear over their skull portrait and tick to 0. If the number's position/size is off, the font size + colour are sliders; tell me and I can add a position nudge.

## 0.2.25-dev (2026-06-19) — Fix UI Tweaks buff-bar end-time crash spam (stacking buffs)

### Fixed
- **UI Tweaks (HideBuffs) `PriorityBuffUI.lua:228: attempt to compare nil with number`** — diagnosed from a player console log spamming it ~1000×/session (once per frame, both buff bars) while a stacking buff was active (repro: Bardin Outcast Engineer pump stacks, `bardin_engineer_pump_buff`). `_add_buff` merges a re-applied buff with `data.end_time = end_time and ((data.end_time < end_time and end_time) or data.end_time)` — the `end_time and …` guard protects only the *incoming* end-time; if the *stored* `data.end_time` is nil (buff first added while infinite, then refreshed with a finite end-time) the compare is `nil < number` and throws.
  - **Fix:** new `gut_compat_group` toggle **`gut_buffbar_endtime_fix`** (default ON). Wraps the global `PriorityBuffUI._add_buff`, mirrors its own match loop, and backfills only the single entry it will act on (stored nil end-time + finite incoming) with the incoming end-time before the compare runs. Result: the vanilla compare evaluates to false and keeps the refreshed end-time — no crash, no visible change beyond stopping the spam. Pure-Lua wrap of stock UI Tweaks (no forked resources); read live so the toggle reverts instantly; no-op if UI Tweaks isn't installed. New file `_gut_buffbar_endtime_fix.lua`, wired beside the Temporal Fix (load + `on_all_mods_loaded` retry + immediate try).

## 0.2.24-dev (2026-06-19) — Absorb UI Tweaks (HideBuffs), Phase 1: hide UI elements / hide buffs / loading-screen hides

First phase of porting UI Tweaks (HideBuffs) into gut so you can drop the standalone mod. Fork-and-renamespace: the forked Lua lives under `scripts/mods/gui_tweaker/hb/` with `get_mod("HideBuffs")` → `get_mod("gut")`. **Disable the standalone "UI Tweaks" mod once gut covers what you use, to avoid double-hooking.**

### Added (28 settings, group "UI Tweaks (absorbed)")
- `hb/hb_data.lua` — the data backbone (SETTING_NAMES, alignments, portrait-icon maps, etc.), with HideBuffs' VMF options-tree construction stripped (gut registers the tree statically). Penlight (`pl`) is globally available in VT2, so no bundling needed.
- `hb/hide_elements.lua` — the self-contained single-element hide hooks: `ChallengeTrackerUI._draw`, `TutorialUI.*`, `MissionObjectiveUI.draw`, `BossHealthUI._draw`, `GameModeManager.has_activated_mutator` (hide-HUD-when-inspecting), `IngameHud._update_components_visibility`, `OutlineSystem.always` (pickup/objective outlines), `DialogueSystem.*`/`SubtitleGui`/`PlayerHud`/`TwitchVoteUI`/`WaitForRescueUI`/`TwitchIconView`, and `UnitFrameUI._update_bar_flash` (stop white-HP flashing). Plus the **Hide-HUD hotkey** (`HIDE_HUD_HOTKEY` keybind → `mod.hide_hud`).
- `hb/level_loading_screen.lua` — hide loading-screen tips/subtitles + disable level-intro / Olesya audio.
- Settings: **Hide UI Elements** (17, incl. boss HP bar, levels, frames, outlines, new-area popup, loading tips/subtitles, intro audio, twitch icon, rescue message), **Hide Active Buffs** (9 per-class passive/grimoire hides), and root toggles (default portrait frames, unobtrusive objective/mission markers). All ids kept verbatim from HideBuffs so the forked hooks resolve.

### Notes
- Skipped the `mod_events` lifecycle backbone this phase — the hide hooks are draw-time + the keybind auto-wires, so it isn't needed yet (it comes with the buff/unit-frame phases, along with its Phase-2+ guards).
- Phases 2–5 (ammo counter, equipment UI, unit frames + portraits + temporal-fix reconciliation, buff bars, dodge counter) follow.

## 0.2.23-dev (2026-06-19) — Temporal-fix offset now tunable; Parry Indicator hardened + diagnostic

### Temporal fix — health-bar offset reported "wrong direction"
My port faithfully reproduces Isaakk's Nov-2024 values (`size/2 + 50`), but a later game patch can move the correct spot. Made the horizontal placement a **slider** — `gut_temporal_hp_nudge_x` (range ±400, default 0 = the original fix), nested under the Temporal Fix toggle — so it can be dialled either way without a rebuild (negative = pull left). Added a one-shot debug line logging the bar's `size_x -> offset_x` so the right value is readable from the log.

### Parry Indicator — "isn't working"
The install log showed `toggle: false` — it's **off by default**; enable **Parry Indicator** in gut's settings. Also hardened it:
- Recolour now runs **after** the original `update_shields` and **mutates RGB in place** (indices 2-4) instead of replacing the whole color table — leaving alpha to the game's fade animation (verified: vanilla `update_shields` only writes `style.color[1]`).
- Added debug lines (`[gut:parry] update_shields hook live: N shields…` once, and `timed-block window ENTER` on each block) so if it's enabled and still not visible, the log shows whether the hook fires and the window is detected.

## 0.2.22-dev (2026-06-19) — Fix Mod Tweaker VMF enumeration (correct field names from the in-game probe)

The v0.2.20 auto-populate showed only gut's dogfood tab (`[mt] rebuild: total=1 … rows=2`). The in-game debug probe revealed why: VMF's real fields are `mods` / `mods_unloading_order` / `options_widgets_data` — **no leading underscore** (the reverse-engineered guess `_mods_unloading_order` was nil, so the enumeration bailed).

### Fixed
- `_mod_tweaker_view.lua` `_vmf_categories()` now iterates `vmf.options_widgets_data` directly: each per-mod list's `[1]` header carries `mod_name` + `readable_mod_name` (confirmed flat via the probe), `[2..]` are the setting nodes; the mod object for get/set is `get_mod(mod_name)`. So every VMF mod with options should now get a tab populated with its real settings.
- Enhanced the debug probe to also log the first real setting node's keys + types (`[mt] vmf node[n][2] …`), so the per-widget shape (label/value field names) is visible for the next round if any node-level field needs adjusting.

## 0.2.21-dev (2026-06-18) — Absorb Bestiary + Armory as one self-populating compendium (data layer)

Merging the standalone **Armory** (weapon compendium, Workshop 1464907434) and **Bestiary** (enemy compendium, Workshop 1431393962) mods into gut as a single feature, rebuilt with a **pure-dynamic data layer** — content is enumerated live from the game's own tables, so new weapons/enemies (Necromancer, Beastmen, undead, DLC specials) appear automatically with no hardcoded roster to go stale. This phase lands the data providers + console probes; the HeroView compendium UI follows.

### Added
- `_ba_weapon_provider.lua` — enumerates `ItemMasterList` (keep `has_power_level` + weapon `slot_type`), groups by `can_wield` (engine source of truth, auto-handles cross-career weapons like the flail and new careers like Necromancer), resolves name/icon/3D-units/illusions, derives attack chains. Lazy-built cache.
- `_ba_enemy_provider.lua` — enumerates `Breeds` filtered to combat AI breeds (`is_ai` + race ∈ skaven/chaos/beastmen/undead, minus critters/dummies/pets). Per-breed attributes ported verbatim from the original Bestiary (difficulty-scaled health/mass/stagger arrays, armor category, boss/elite/special). Replaces the original's hardcoded skaven/chaos/beastmen roster + icon-slot tables. Variant (shielded/commander/warlord/boss) grouping derived dynamically by suffix.
- `_ba_attack_labeler.lua` — derives a weapon's light/heavy/push (melee) and ranged/alternate (ranged) attack chains + labels from `Weapons[template].actions`, replacing the original Armory's hand-authored `armory_wanted_attack_list`.
- `_ba_compendium.lua` — feature entry; wires the providers + commands. Dofile'd from `gui_tweaker.lua`.
- Commands: `/gut_ba_dump_weapons` and `/gut_ba_dump_breeds` (paste-ready console dumps to verify the live enumeration), plus `/gut_armory` and `/gut_bestiary` (open commands; UI pending).

### Notes
- Pure-dynamic by design (no curated preview offsets or attack labels) per direction — generic framing + generated labels, refined in-game later.
- Single-hook discipline preserved: the compendium will add exactly one `HeroView.init` and one each `HeroViewStateOverview.create_ui_elements`/`_handle_input` hook in the UI phase (gut currently hooks only `HeroView.on_enter`, so no collision).

## 0.2.20-dev (2026-06-18) — Mod Tweaker auto-populates a tab per VMF mod, with that mod's real options

The Mod Tweaker now discovers every installed VMF mod and renders one tab each, populated from that mod's real settings — edits write straight to the live mod (firing its `on_setting_changed`). (Mapped VMF's runtime data model via a workflow, since VMF ships as bytecode.)

### Added
- **Auto-discovery** (`_mod_tweaker_view.lua`): enumerate `get_mod("VMF")._mods_unloading_order`; each mod's flattened widget list comes from `get_mod("VMF").options_widgets_data` (matched by `mod_name`). Excludes VMF itself; gut appears with its real settings. Sorted enabled-first then alphabetically; disabled mods marked `*`.
- **Real get/set routing**: `mod_obj:get(id)` / `mod_obj:set(id, value, true)` (3rd arg fires the mod's `on_setting_changed` so it reacts live; VMF persists automatically). The gut controller path remains for any non-VMF category.
- **Widget-type coverage**: checkbox + numeric (`[<]`/`[>]` stepper) are editable; **dropdown** is an option cycler; group titles + keybind/text show read-only. Field reads are defensive (flat or `content`-wrapped) and pcall-guarded.
- **Tab paging**: the strip fits 8 tabs; with more mods it shows 7 + a `More N/M >` tab that pages through all of them (so every mod is reachable). Long names truncated.
- **Debug probe**: with debug logging on, logs VMF's actual table fields + a sample node's keys once, so the real bytecode shape is visible if any reverse-engineered field name is off.

### Known limitations (follow-ups)
- No row scrolling yet — a mod with many settings draws past the list area (clipped, no crash).
- Dropdown `show_widgets` sub-reveal not handled (all options shown); keybind/text not yet editable.

## 0.2.19-dev (2026-06-18) — Absorb the Parry Indicator (works on every weapon)

Ported the **Parry Indicator** mod (Workshop 1459917022) into gut as an optional toggle, with one deliberate change: it now works **regardless of whether the current weapon has the Parry trait**.

### Added
- `_gut_parry_indicator.lua` — recolours the HUD block/stamina shields (`FatigueUI.update_shields`) during the **timed-block window**: the first 0.5s after raising block, while actively blocking and not mid push / attack / revive / pull-up / assisted-respawn (the action-exclusion hooks are ported verbatim). Verified VT2 internals: `FatigueUI.self.shields[].style.color`; `GenericStatusExtension.raise_block_time` + `.blocking` (status_system extension).
  - **Change from the original:** the original gated the cue on the weapon carrying the Parry trait (tracked via the `timed_block_cost` stat buff). gut **drops that gate** — the BuffExtension `has_parry` tracking is omitted entirely — so the timing cue shows on every weapon (the timed-block window exists for all weapons; Parry just makes blocks in it free).
- Settings (group **Parry Indicator**, default **off**): `gut_parry_indicator` toggle + `gut_parry_r/g/b` colour (0-255, defaults 0/255/120 — a parry teal, matching the original).
- Duplicate-hook preflight: none of `FatigueUI`/`ActionPushStagger`/`ActionSweep`/`InteractionDefinitions.*` were hooked elsewhere in gut.

## 0.2.18-dev (2026-06-18) — Fix Mod Tweaker render crash (`checkbox_checked not found in Gui`)

The menu now opens, but crashed on the first row: `ui_passes.lua:134: Material 'checkbox_checked' not found in Gui`.

### Root cause
Reused the native `options_view_definitions` checkbox/slider factories, which reference **raw (non-atlas) materials** — `checkbox_checked`, `checkbox_unchecked`, `rect_masked`, `highlight_texture` — that appear only inside that file and in no atlas. They aren't present in the borrowed in-game renderer's Gui, so the first texture pass crashed. (Classified every row material against `scripts/ui/atlas_settings/` to confirm which are atlas-backed vs raw.)

### Fixed
- **Rebuilt the row widgets** from things that resolve on the borrowed renderer: `rect`/`border` passes (no material lookup) + atlas-backed textures resolved globally by `UIAtlasHelper` whose master atlas is resident (proven: hero_view keep states render these on this renderer) — `matchmaking_checkbox` (checkbox marker) and `slider_thumb`. No more raw materials.
  - **Checkbox**: rect box + border + atlas check marker + label; whole-row hotspot toggles it.
  - **Numeric**: label + rect track + fill + atlas thumb + `[<]`/`[>]` click zones + value text (stepper; `step ≈ range/40`, min one display unit). Drag-to-set can come later.
- **Draw on `ui_renderer`** (level_world) instead of `ui_top_renderer` — it carries the full settings-menu material set (the renderer OptionsView/hero_view use for their checkbox/slider widgets).
- **Dropped the scrollbar** from the draw (its OVD definition also uses raw `rect_masked`/`mask_rect`); the list is short. Revisit with a rect-based scrollbar when scrolling is added.

## 0.2.17-dev (2026-06-18) — Fix Mod Tweaker not opening + `<>` localization

Two bugs reported after v0.2.16 shipped: the Mod Tweaker menu didn't open, and menu entries rendered as raw keys in angle brackets (`<…>`).

### Fixed
- **Menu didn't open.** The `IngameUI.setup_views` post-hook saw `self.views` as not-yet-a-table (the game's Versus update shifted when `self.views` is populated relative to `setup_views`), so the view never attached and the ESC transition correctly no-op'd. Now the view is **lazy-attached in the transition closure** — at click time the IngameUI is fully initialised (`self.views` + `self.ingame_ui_context` both set, `ingame_ui.lua:138`), which is the reliable build point. Extracted `_attach_view()` (idempotent), used by both the setup_views hook (early attempt) and the transition (guaranteed path). On dofile/`:new` failure it logs and stays a no-op rather than crashing.
- **`<mod_tweaker_button_name>` ESC entry.** The ESC button localizes its `display_name` through the GLOBAL `Localize()`, where VMF mod localization is NOT registered — so the key rendered literally. Added a guarded `_G.Localize` hook resolving our one key to "Mod Tweaker" (duplicate-hook preflight: no other gut Localize hook).
- **`<Tweaker: GUI>` tab labels** (would have shown once the menu opened). `UIWidgets.create_text_button` forces `localize=true` on its text styles; `create_tab` now disables `localize` on every text style so the raw category label renders.

## 0.2.16-dev (2026-06-18) — Absorb the "UI Tweaks Temporal Fix" (player health-bar placement)

Researched and reimplemented the removed/unsanctioned standalone mod **"UI Tweaks Temporal Fix"** (Isaakk, Workshop 3366928597) as a clean, sanctioned patch inside gut. Despite the name it has nothing to do with temporal reprojection — it re-aligns the **player's own health bar** in UI Tweaks' (HideBuffs) **mini-HUD layout**, which the game's Versus update knocked out of place.

The exact fix was recovered by bytecode-diffing 3366928597 against stock UI Tweaks (1467751760), both decompiled with the same tool so only Isaakk's change remained:
- `player_unit_frame_ui.lua` (`player_unit_frame_draw`, MINI_HUD_PRESET branch): `total_health_bar` / `hp_bar` / `hp_bar_highlight` `.offset[1]` sign-flip `-size/2` → `+size/2 + 50`; `ability_dynamic.offset[1]` `0` → `-2`.
- `content_change_functions.lua` (player grimoire divider + bar): `offset[1]` shifted left by `58 * hp_bar_w_scale`.

### Added
- `_gut_uitweaks_temporal_fix.lua` — wraps the three PUBLIC HideBuffs functions (`player_unit_frame_draw`, `player_grimoire_debuff_divider_content_change_fun`, `player_grimoire_bar_content_change_fun`): calls the original, then re-applies the corrected offsets. Pure-Lua, sanctioned (no forked engine resources, unlike Isaakk's mod). Installed at `on_all_mods_loaded`; idempotent; no-op when UI Tweaks isn't installed. Gated on the toggle and read live each frame so toggling reverts instantly.
- Setting **`gut_uitweaks_temporal_fix`** (group "UI Mod Compatibility"), default **on**.

### To verify (in-game)
- With UI Tweaks installed + its mini-HUD layout active, your own health bar should sit correctly (not shoved off to one side). Toggle the setting off to compare against the broken vanilla-UI-Tweaks placement.

## 0.2.15-dev (2026-06-17) — Mod Tweaker: native settings-menu chrome (reuse OptionsView pieces)

Replaced the crude rect placeholders with the REAL Options-menu look, by reusing the native pieces instead of hand-rolling. Full inventory of `options_view_definitions` taken (verified 2026-06-17).

- `_mod_tweaker_definitions.lua` — now `local_require`s the native `options_view_definitions` and assembles from it: clones the native `scenegraph_definition` (so the 1400×900 window, frame, top/bottom panels, `list_mask`, scrollbar nodes all exist + lay out identically), builds the chrome from `background_widget_definitions` (the `menu_frame_12` border, `{255,10,10,10}` panels, `cogwheel_small` symbol), the native `scrollbar_definition`, and the native `exit_button` (`friends_icon_close`). Adds a horizontal tab strip (`mt_tab_N`) + a list anchor (`mt_list_start`) under `list_mask`. Tabs are `UIWidgets.create_text_button` (idle→white-on-hover/selected); rows are the native `create_checkbox_widget` / `create_slider_widget`.
- `_mod_tweaker_view.lua` — rebuilt to draw the native chrome + tab strip + native rows + scrollbar in one `begin_pass`. Native checkbox flips `content.flag` in its own pass; native slider updates `content.value` via its passes; the view reads those and persists on change. Each row's native factory call is `pcall`-guarded (one bad row can't blank the menu) and logged. Render-state probe (`[mt:dump]`) + heartbeat retained.

### To verify (in-game, debug logging on)
- ESC → Mod Tweaker should now show a framed window (menu_frame_12 border, dark panels, cogwheel top-left, X close top-right) with a **Tweaker: GUI** tab across the top and native-style checkbox/slider rows. Send the `[mt:dump]` lines if anything's off.

## 0.2.14-dev (2026-06-17) — Mod Tweaker render-state probe (diagnostic only)

The view opens with no errors (log: `ModTweakerView attached`, no nil/texture/font failures), so nothing is failing to render — but the menu doesn't look like the native settings menu, and our logging only caught render *errors*, not widgets that render fine yet sit off-screen / zero-size / invisible. This build adds that missing visibility (instrument only — no behavior change yet):

- `_mod_tweaker_view.lua` — `_dump_state()` logs, on view open (`[mt:dump]` lines, debug-gated): category/tab/row counts, the on-screen world position + size of `panel` / `tab_area` / `list_area` (vs the 1920×1080 screen), and each tab's/row's offset/size/value. So the log alone shows whether elements are positioned, sized, and on-screen.
- `_mod_tweaker_view.lua` — per-~2s **draw heartbeat** (confirms `update`/`_draw` is running and how many widgets it draws) + **input-event logging** (tab click / checkbox toggle / slider drag) so we can see input reaching the widgets.

No widget/visual changes — the next log tells us whether this is a layout/visibility bug or just needs the native widget art, before rebuilding.

## 0.2.13-dev (2026-06-17) — Fix: view missing required IngameUI contract methods (input_service crash)

v0.2.12 fixed construction (the view now attaches — log confirms `[mt] setup_views: ModTweakerView attached`), but opening it then crashed `ingame_ui.lua: attempt to call method 'input_service' (a nil value)`: IngameUI calls `active_view:input_service()` **unconditionally** every frame (ingame_ui.lua:416/770) and the view didn't implement it.

### Fixed
- `_mod_tweaker_view.lua` — added the three view-contract methods IngameUI calls unconditionally on the active/new/old view: `input_service()` (returns the view's input service), and no-op `post_update_on_enter(params)` / `post_update_on_exit(params, was_replaced)` (called on every view transition — would have crashed on open/close next). The other contract methods (`current_state` / `disable_toggle_menu` / `hotkey_allowed` / `set_map_interaction_state` / `is_survey_*`) are guarded with `if view.method` in IngameUI and are safely omitted.

## 0.2.12-dev (2026-06-17) — Fix: Mod Tweaker view crashed IngameUI (nil view on open)

In-game test of v0.2.11 crashed on opening the Mod Tweaker: `ingame_ui.lua:625: attempt to index a nil value` (current_view = "mod_tweaker_view"). Root cause: `IngameUI.init` passes the context to `setup_views(ingame_ui_context)` as an **argument** (ingame_ui.lua:107) and does NOT store `self.ingame_ui_context` at that point — the scaffold hook read `self.ingame_ui_context` (nil), so `ModTweakerView:new` threw, the view never attached, and transitioning to the missing view indexed `views[current_view]` = nil → hard crash.

### Fixed
- `gui_tweaker.lua` — the `setup_views` hook now captures the **`ingame_ui_context` argument** (`function(self, ingame_ui_context)`) and builds the view from it; refuses to attach a context-less view.
- `gui_tweaker.lua` — the `mod_tweaker_view` transition closure now switches `current_view` only if `self.views.mod_tweaker_view` exists, so a missing view can never crash IngameUI (the ESC entry becomes a no-op instead).
- `_mod_tweaker_view.lua` — `init` errors clearly on a nil context (caught by the hook's pcall) instead of failing mid-body.

(Unrelated: the log also shows a pre-existing VMF/Loremasters-Armoury tooltip error in `vmf_options_view` via the deprecated `_G.UIResolutionScale_pow2` — not part of gut.)

## 0.2.11-dev (2026-06-17) — Mod Tweaker view: first renderable pass (tasks #6–8)

The Mod Tweaker (the in-game settings menu for all the Tweaker mods, opened from the ESC menu) now actually **renders** — previously the view was a stub and clicking the ESC entry opened nothing. Built from the verified VT2 `OptionsView` contract (read 2026-06-17): borrows the IngameUI renderer, registers a modal input service, draws in one `begin_pass`/`end_pass`, and returns to the ESC menu via `ingame_ui:transition_with_fade("ingame_menu")`.

### Changed
- **`_mod_tweaker_definitions.lua`** — real scenegraph (root/screen-dim/panel/title/left tab strip/right list/hint) + widget factories (panel, title, hint, tab, checkbox, slider). Deliberately atlas-free (`rect`+`text`+`hotspot` passes only) so the first on-screen pass can't fail on a missing texture; visual polish (proper checkbox/slider art) is a later pass. Per-row/per-tab hotspot styles give correct hit regions.
- **`_mod_tweaker_view.lua`** — replaced the stub with a working `ModTweakerView`: init borrows the context renderer + registers the `gut_mod_tweaker` input service; `on_enter` shows the cursor + makes the view modal + builds tabs/rows from the registered categories; `update` draws and handles input; checkbox click toggles + persists, slider drag sets value + persists (both through the controller `mod.mod_tweaker` so there's a single registry); `exit` transitions back to the ESC menu. Reads the registry via the controller (NOT a fresh `_mod_tweaker_settings` dofile, which would be empty).
- **`gui_tweaker.lua`** — registers a dogfood `gut` category (debug-logging checkbox that bridges to VMF + a demo slider) so the view shows real, interactive content end-to-end.

### To verify (in-game)
- In a mission or the keep, press ESC → click **Mod Tweaker** (above Options). A panel should open with a "Tweaker: GUI" tab on the left and two rows: a Debug-logging checkbox (click toggles ON/OFF) and a demo slider (drag to change the value). ESC closes back to the ESC menu. `/gut_regression_test` still passes the mod_tweaker entry/transition checks.

## 0.2.10-dev (2026-06-16) — `/gut_lua_mem` diagnostic (Lua-heap footprint measurement)

### Why
A friend (nicho) hit the VT2 hard crash `Not enough memory reserved for heap lua_heap` (reserved 1073741824 = 1 GiB, `heap_allocator.cpp:227`) at mission load while running ~58 mods incl. the now-public Tweaker mods — the Lua heap was pinned at 100% (1 GiB used of 1 GiB). The `lua_atpanic/lua_close` callstack is the symptom, not the cause. To attribute footprint per-mod (which can't be read off source line counts — it's a runtime quantity) we need a live measurement.

### Changed
- `gui_tweaker.lua` — new `/gut_lua_mem [label]` command: forces a full GC and prints live Lua memory (`collectgarbage("count")`) in MB. Per-mod workflow: disable suspects → launch → load a level → `/gut_lua_mem baseline`; enable one mod → relaunch → `/gut_lua_mem <mod>`; the jump is that mod's footprint. (Lower-bound proxy: the engine `lua_heap` also holds bytecode + C-side Lua structures; compare deltas, not absolutes.)

## 0.2.9-dev (2026-06-16) — Phase 0: fix Versus host-crash in vanilla damage-feedback (UI-absorption groundwork)

### Why
First step of absorbing NumericUI + UI Tweaks (HideBuffs) into gut against the current GUI. The reported Versus host-crash is a **vanilla** bug, independent of any rendering: `UnitFrameUI.add_damage_feedback` (`unit_frame_ui.lua`) assigns `self._damage_widgets[order_index]` and sets `widget.content.visible = true` (vanilla L1687-1690 / L1699-1702) for a NEW event *before* the over-MAX eviction at the bottom — and that eviction is dead-coded behind `fassert(false)` (vanilla L1724-1725). When more than `#self._damage_widgets` (4 with damage feedback on) distinct damage events are active at once, `order_index` exceeds the pool, the widget is `nil`, and `widget.content.visible = true` is a fatal index-of-nil. On the **host** it crashes the whole session. Reproduced in Versus by a Pactsworn Ratling Gunner's sustained machinegun fire stacking 5+ simultaneous damage messages on one hero frame (crash GUID `59ae9a93-…`, 2026-06-15). NumericUI re-news the vanilla `UnitFrameUI`, keeping this vanilla path live — but the bug is vanilla and the fix is independent of NumericUI.

### Changed
- `gui_tweaker.lua` — new `mod:hook("UnitFrameUI", "add_damage_feedback", …)` (the mandatory pre-flight grep confirmed gut had no prior `UnitFrameUI` hook). The wrapper drops the **overflow** event before it reaches the nil-widget index — only when the pool is already full AND a new `order_index` would be assigned (a brand-new event, or a re-activated `disabled` one). Existing active events pass through untouched. No vanilla state is mutated (pure pre-call guard; degrades safely if the vanilla shape drifts). The cap is self-healing: vanilla `_update_damage_feedback` removes expired events from `_hash_order` (`table.remove`, vanilla L1819), freeing slots. Perf-gated: the hash/lookup work only runs in the rare at-capacity case. Always-on (a safety guard, not a toggled feature). Decision rule extracted to `mod._gut_damage_feedback_should_drop` for testability.

### Tests
- New `/gut_regression_test` check `damage_feedback_overflow_guard` — pins the drop/keep decision across boundary cases (full pool + new → drop; free slot + new → keep; existing event → always pass through; empty pool → drop).

### To verify (in-game)
- Host a Versus match (host-side crash), keep Numeric UI enabled for now, play a Pactsworn Ratling Gunner and hold sustained fire on heroes — confirm **no host crash** (the 5th+ simultaneous damage message is silently dropped instead). Then `/gut_regression_test` → `PASS: damage_feedback_overflow_guard`.

## 0.2.8-dev (2026-06-07) — HUD drag preserves each widget's vanilla baseline

### Why
Audit 2026-06-07 (F5, HIGH). `_apply_offset_to_scenegraph` wrote the RAW drag delta straight into `node.local_position[1]/[2]`, discarding each widget's non-zero vanilla baseline. The vanilla `HudCustomizer.run` (decompiled `scripts/ui/hud_ui/hud_customizer.lua:119-122`) can assign the raw offset only because the nodes IT customizes baseline at `{0,0}` — its `offset_registry` value IS that node's `local_position`. Our REGISTRY targets real HUD widget nodes whose baselines are non-zero: `equipment_ui` pivot `{0,69}`, `buff_ui` pivot_root `{150,18}`, `boss_health` pivot_parent `{0,-72}`, `challenge_tracker` pivot `{1,155}`, `loot_objective`/`news_feed` etc. So the first drag (even a tiny one) snapped those widgets to screen origin instead of moving them by the delta. `reset_widget` already wrote `entry.vanilla_position` back, confirming that field is the correct baseline reference — the drag path just wasn't using it.

### Changed
- `_hud_customizer.lua:106-134` — extracted the position math into a new exported `CustomizerModule.local_position_for(widget_id, dx, dy)` that returns `vanilla_position + delta` (reads `REGISTRY_BY_ID[widget_id].vanilla_position`, degrades to `{0,0}` baseline for unknown ids). `_apply_offset_to_scenegraph` now calls it instead of assigning the raw `dx, dy`. Baseline preserved; pure delta applied. No new hooks (the two call sites — `_reapply_all_offsets` and the per-class `init` hook body in `install_hooks` — already pass the registry entry's data through `widget_id`).
- `gui_tweaker.lua:578-611` — added `_rt_register("hud_offset_preserves_vanilla_baseline", ...)`. Registered next to the `gut_*` HUD commands (after the `Customizer` dofile) because it closes over `Customizer`.

### Tests
- `/gut_regression_test` → new `hud_offset_preserves_vanilla_baseline` check. Asserts `local_position_for("equipment_ui", 25, -40)` == `{25, 29}` (baseline `{0,69}` + delta), `local_position_for("buff_ui", 0, 0)` == `{150, 18}` (zero-drag returns exact baseline — the old raw-write returned `{0,0}` here), and unknown ids degrade to `{0,0}+delta`. Fails if the baseline term is dropped again.

### To verify
- `/gut_edit_hud`, then drag `equipment_ui` (ammo/equipment cluster), `buff_ui` (buff icons), and `boss_health` a small amount — they should track the cursor smoothly from their current on-screen spot, NOT jump to the screen origin on the first click-drag.
- `/gut_reset_hud` should still snap each widget back to its vanilla position (unchanged path).
- `/gut_regression_test` reports the new check PASS.

## 0.2.7-dev (2026-05-30) -- Loc integrity: ESC-menu button loc key

### Why
`qa/check_name_integrity.ps1` check #2 flagged `display_name = "mod_tweaker_button_name"` (gui_tweaker.lua:627) — the ESC-menu "Mod Tweaker" button entry assigned a loc key that resolved in no loc table. The vanilla ingame_view render path runs the button's `display_name` through Localize (style `localize = true`, ingame_view.lua:138-140 + :252), and `display_name_func` is a dead vanilla field never invoked — so the button rendered the raw key string instead of "Mod Tweaker".

### Changed
- `gui_tweaker_localization.lua` — added `mod_tweaker_button_name = { en = "Mod Tweaker" }` (matches the intent of the existing `display_name_func` that returned "Mod Tweaker").

### Notes
- Resolves the gui_tweaker entry in the 13 check_name_integrity errors.

## 0.2.5-dev (2026-05-25) -- Restore dev/alpha/beta load banner (PROJECT_STANDARDS § 3.6 update)

### Why
User feedback 2026-05-25 EOD: earlier today's chat-spam cleanup pulled the `mod:echo("<Name> v" .. MOD_VERSION)` startup line from every mod. That's correct for stable (>=1.0.0) builds but hides the active version for in-flight dev/alpha/beta work. PROJECT_STANDARDS § 3.6 amended: dev/alpha/beta/0.x versions MUST echo `[<mod_id>] v<version> loaded` at module load; stable versions stay silent.

### Changed
- `gui_tweaker.lua` -- added a track-detector `if` after the applied-marker line: matches `-dev$` / `-alpha$` / `-beta$` / `-rc%d*$` / `^0%.`. When any branch fires, `mod:echo("[gut] v<MOD_VERSION> loaded")` runs once.

## 0.2.4-dev (2026-05-25) -- Fix unescaped %APPDATA% in Debug Logging tooltip + add localization_format_safe runtime test

### Why
User report: "invalid string format on mouseover for Debug Logging" -- the canonical Universal Debug Logging tooltip (PROJECT_STANDARDS.md S 3.6) shipped with a literal %APPDATA%. Lua's string.format reads %A as a format directive and raises invalid option '%A' to 'format', surfacing as a red error tooltip in the VMF settings UI. All 16 active mods were affected (every mod ships the same canonical tooltip text).

### Changed
- gui_tweaker_localization.lua -- escaped literal % in enable_debug_logging_tooltip so VMF's tooltip render path sees %%APPDATA%% (renders as %APPDATA% to the player). Same wording, just escaped.
- gui_tweaker.lua -- added _rt_register("localization_format_safe", ...) runtime check. dofiles the loc table and pcall(string.format, value) on every entry; surfaces any unescaped % via /<mod_id>_regression_test. Catches the bug class even when the static check (qa/check_localization.ps1) is skipped.

### Notes
Repo-wide multi-layer defense landing across all 16 mods in this sweep:

1. Layer 1 -- 16 mods' loc strings fixed.
2. Layer 2 -- qa/check_localization.ps1 extended to parse loc.<key> = { en = "..." } assignment style (chaos_wastes_tweaker's pattern -- previously slipped detection).
3. Layer 3 -- _rt_register("localization_format_safe", ...) runtime check in every mod.
4. Layer 4 -- tools/vmb-launcher/CLAUDE.md doctrine update: "Run qa/check_localization.ps1 before declaring any localization edit complete."
5. Layer 5 -- documentation: LOCALIZATION_STANDARD.md S 1 "Recurring offender" worked example, docs/BUG_CLASSES.md S 16 new entry, PROJECT_STANDARDS.md S 3.6 canonical tooltip text now uses %%APPDATA%%.

Static check (qa/check_localization.ps1) reports 0 errors post-fix (down from 15 detected + 1 hidden in chaos_wastes_tweaker).

### Build
VMBLauncher.exe build gui_tweaker -- verification only. NOT deployed, NOT uploaded.

## 0.2.3-dev (2026-05-25) — Applied marker (universal — PROJECT_STANDARDS.md § 3.6)

### Why
Every mod now prints a single `mod:info("[gut] enabled v<X.Y.Z> settings_fp=<8-hex>")` line at load — self-documenting console_logs. Walks the data widget tree, FNV-1a-32 hashes setting=value pairs. ALWAYS fires (not gated on debug_logging).

### Changed
- `gui_tweaker.lua` — added file-local `_settings_fingerprint()` helper + `mod:info("[gut] enabled ...")` applied-marker line right after the `_dbg_alert` helper.
- `itemV2.cfg` — bumped to v0.2.3-dev.

## 0.2.2-dev (2026-05-25) — Fix dead `NewsHeadUI` hook (issue #41)

### Why
Two `[MOD][gut][ERROR] (hook_safe): trying to hook object that doesn't exist: NewsHeadUI` lines fired every session. The HUD customizer's REGISTRY (`_hud_customizer.lua` line 23) used `class_name = "NewsHeadUI"`, but vanilla VT2's news-feed widget class is named `NewsFeedUI` — the file lives at `scripts/ui/hud_ui/news_feed_ui.lua`. The two error lines came from `install_hooks` iterating REGISTRY and registering both `init` and `destroy` hooks (lines 264 and 268) against the non-existent class.

### Changed
- `_hud_customizer.lua` line 23 — renamed `class_name` `NewsHeadUI` → `NewsFeedUI`, and `definitions_file` documentation reference from `news_head_ui_definitions.lua` → `news_feed_ui_definitions.lua` (the actual vanilla path).
- `gui_tweaker.lua` — `MOD_VERSION` bumped 0.2.1-dev → 0.2.2-dev.
- `itemV2.cfg` — title bumped to v0.2.2-dev.

### Notes
- `scenegraph_node_id = "pivot"` is correct — confirmed against `news_feed_ui_definitions.lua` scenegraph_definition.
- Result: the news-feed HUD widget is now actually drag-repositionable in `/gut_edit_hud` instead of being silently absent from the live-views table.

### Closes
- #41 (gut hook_safe target `NewsHeadUI` doesn't exist — 2 silent dead hooks).

## 0.2.1-dev (2026-05-25) — Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6)

### Why
User-requested two-channel debug discipline: `_dbg` for confirmation / dump / expected behavior (log file only), `_dbg_alert` for unexpected / wrong / mismatch (log file + in-game chat). Helpers installed in every active mod. gui_tweaker previously had no `_dbg` helper at all.

### Changed
- `gui_tweaker.lua` — added file-local `_dbg(fmt, ...)` and `_dbg_alert(fmt, ...)` helpers at top. Output prefix `[gut:dbg]` / `[gut]`.
- `gui_tweaker.lua` — promoted the previous one-line `/gut_regression_test` stub to a proper `_RT_CHECKS` scaffold and registered `dbg_helpers_two_channel`.
- `itemV2.cfg` — bumped to v0.2.1-dev.

### Notes
- 0 existing `_dbg(...)` call sites (helper was newly introduced).
- 0 bare `mod:echo` reclassified — every `mod:echo` in `gui_tweaker.lua` is either inside a `/gut_*` chat command body (user-operational) or is the unconditional `hud-customizer hook install failed` operational error at line 306. Both classes are correct as bare `mod:echo` per the policy.
