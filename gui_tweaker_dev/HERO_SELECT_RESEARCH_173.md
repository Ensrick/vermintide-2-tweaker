# Issue #173 — "Hero Select opens Talents, not the hero/career selection screen"

Source-verified research. Every view name, function, field, and line citation below was
confirmed by grep/read against the decompiled vanilla source at
`C:\Users\danjo\source\repos\Vermintide-2-Source-Code` and the gut_dev source. Paths are
relative to those two roots.

READ-ONLY research doc. No existing mod file was edited to produce this.

---

## TL;DR — what the hero/career selection screen actually IS, and why gut lands on Talents

VT2 registers **two completely separate top-level views** in
`scripts/ui/views/ingame_ui_settings.lua:732-743` (`views_function`):

- **`hero_view = HeroView:new(...)`** (line 736) — the loadout / **talents** / cosmetics /
  forge / prestige management screen. It has ONE view with named sub-layouts inside
  `HeroViewStateOverview`: `equipment`, `talents`, `forge`, `cosmetics`, `prestige`
  (`scripts/ui/views/hero_view/states/definitions/hero_view_state_overview_definitions.lua:222-276`).
- **`character_selection = CharacterSelectionView:new(...)`** (line 737) — the actual
  **hero/career PICK grid** (the "C" key screen; "switch character here"). Its screen states
  are `character` (`CharacterSelectionStateCharacter`) and `loadouts` (versus only)
  (`scripts/ui/views/character_selection_view/character_selection_view_definitions.lua:255-286`).

gut's "Hero Select" (`gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_mission_hero_select.lua:145-149`)
fires:

```lua
Managers.ui:handle_transition("hero_view_force", {
    menu_state_name     = "overview",
    menu_sub_state_name = "talents",
    use_fade            = true,
})
```

That targets **HeroView's `talents` layout** — the Talents screen, verbatim. It never
touches `CharacterSelectionView`. That single mismatched transition is the entire bug: gut
points at the wrong view (`hero_view` / talents) instead of the hero/career pick view
(`character_selection` / `character`).

**The one-line-correct target** (identical to what the keep character-selection pedestal
already fires — `scripts/unit_extensions/generic/interactions.lua:2312-2320`, and what the
`hotkey_hero` "C" hotkey uses — `ingame_ui_settings.lua:769-776`):

```lua
Managers.ui:handle_transition("character_selection_force", {
    menu_state_name = "character",
    use_fade        = true,
})
```

**Why gut hasn't just done that**: `CharacterSelectionView` mounts a **keep/menu-only level
bundle** (`levels/ui_character_selection/world`) with **no managed package load** — so opening
it mid-mission risks the C-level resource-load fatal. That crash risk is real and
source-grounded (details in the lists below), which is why the fix is not a blind one-liner.
The decisive question — is that level bundle resident mid-mission? — is answerable by one
read-only probe (Probe B3) before shipping any rewire.

---

## EMPIRICAL ANCHOR — in-game log (gut_dev v0.2.158-dev, 2026-07-01)

Log: `C:\Users\danjo\Downloads\console-2026-07-01-22.35.00-083eb8cc-3e4e-45f4-91e9-121e44e002b4.log`.
This log confirms every source finding above and settles the "keep-only by design" question.

**(1) The bug reproduced IN A MISSION** (`level_key=military`, two separate firings, lines
~8115-8147 and ~13621-13649):
```
13621  [gut:heroselect] keybind fired -> in_keep=false level_key=military is_in_inn=false (bail=false)
13622  [gt_dev][transition] hero_view_force | mech=adventure level=military in_keep=false ...
13623  [IngameUI] menu view on_enter hero_view
13635  [HeroViewState] Enter Substate HeroViewStateOverview
13637  [gt_dev][menu_dump:layout_talents] === BEGIN ===
 8145  [gt_dev][menu_event] _change_window index=4 name=talents | ... view=hero_view ...
```
In-mission "Hero Select" = `hero_view` forced onto the `talents` layout (window index 4).
Empirical proof of the exact source path in the TL;DR.

**(2) The REAL hero/career selection screen, working IN THE KEEP** (`level_key=inn_level`,
lines ~6324-6468) — gut correctly bails, and the vanilla native entry then drives the true
view:
```
6324  [gut:heroselect] keybind fired -> in_keep=true level_key=inn_level is_in_inn=true (bail=true)
6325  [gt_dev][transition] character_selection_force | ... view=? ...
6326  [IngameUI] menu view on_enter character_selection
6331  [HeroViewState] Enter Substate CharacterSelectionStateCharacter
6332+ [PackageManager] Load: units/beings/player/.../chr_third_person_base, MenuWorldPreviewerCharacterSelectionView, async-read
6404  [gt_dev][ai_slotdump] ... view=character_selection profile=empire_soldier career=es_mercenary   (browsing careers)
6466  [gt_dev][transition] exit_menu | ... view=character_selection ...
6467  [IngameUI] menu view on_exit character_selection
6468  [HeroViewState] Exit Substate CharacterSelectionStateCharacter
```
This is the ground-truth confirmation that vanilla hero/career selection is the **top-level
view `character_selection` with substate `CharacterSelectionStateCharacter`, reached via the
`character_selection_force` transition** — a DIFFERENT view from `hero_view`, not a `hero_view`
tab.

**(3) The misunderstanding was coded into gut's own tooltip by a prior session** (line 9259-9261,
`sid=gut_open_hero_select_hotkey`, `raw_title="Open Hero Select (Mid-Mission)"`):
> "...Calls `Managers.ui:handle_transition('hero_view_force', { menu_sub_state_name = 'talents' })`
> directly... just landing on the Talents tab... Career PICK is NOT available mid-mission
> (keep-only by design...)."

The tooltip documents Talents-as-Hero-Select as if intended, and asserts "keep-only by design"
as fact. **That claim is not backed by vanilla source.** See below.

### The "keep-only by design" claim — REFUTED as a code rule, narrowed to a resource question

Nothing in the vanilla view code hard-gates character selection to the keep:
- `CharacterSelectionView` merely stores `self.is_in_inn = ingame_ui_context.is_in_inn`
  (`character_selection_view.lua:35`) and never asserts on it; there is no `only_in_inn` flag,
  no `fassert(is_in_inn)`, no early-out. (Grep of the whole `character_selection_view/` dir for
  `is_in_inn` returns only that assignment plus the versus-loadouts equivalent.)
- The confirm button's only environmental requirement is an active `Network.game_session()`
  (`character_selection_state_character.lua:1503-1507`) — which EXISTS mid-mission, so that
  guard passes in a live game.

What actually keeps character selection in the keep is therefore (a) **entry-point convention**
— vanilla only offers it via the keep `characters_access` pedestal (`interactions.lua:2312-2320`)
and the `hotkey_hero` hotkey (subject to `default_disable_for_mechanism`), never mid-mission;
and (b) the **unguarded level-bundle mount** of `levels/ui_character_selection/world` (A2/A6/A9),
which is the genuine, and still empirically unverified, mid-mission risk. The log shows
`character_selection` opening only in the keep, where that bundle is resident — it neither
proves nor refutes a mid-mission crash. So "keep-only by design" should be read as "vanilla
never *exposes* it mid-mission, and its level load is unguarded," NOT "the view is coded to
refuse a mission." Probe B3 is the one measurement that resolves it.

---

## LIST A — 10 ways to RESEARCH the issue (executed where possible; findings folded in)

**A1. Grep the transition table + hotkey map in `ingame_ui_settings.lua`.**
DONE. `character_selection_force` (line 476-479) sets `current_view = "character_selection"`
+ `exit_to_game = true`; `hero_view_force` (line 441-444) sets `current_view = "hero_view"` +
`exit_to_game = true`. The `hotkey_hero` entry (769-776) maps the hero/character hotkey to
`in_transition = "character_selection_force"`, `transition_state = "character"`,
`view = "character_selection"`. FINDING: the correct transition name for hero/career pick is
`character_selection_force` with `menu_state_name = "character"`.

**A2. Read `CharacterSelectionView` + its definitions.**
DONE. `post_update_on_enter` (`character_selection_view.lua:519-539`) UNCONDITIONALLY does
`self.viewport_widget = UIWidget.init(widget_definitions.viewport)` then
`self.world_previewer:on_enter(self.viewport_widget, self._hero_name)`. The viewport widget
style (`character_selection_view_definitions.lua:381-406`) has
`level_name = "levels/ui_character_selection/world"`, `world_name = "inventory_preview"`,
`viewport_name = "inventory_preview_viewport"`, and **no `level_package_name`**. FINDING: the
view mounts a specific level directly through the viewport pass.

**A3. Read HeroView's overview sub-layouts.**
DONE. `hero_view_state_overview_definitions.lua:222-276` lists layouts `equipment`,
`talents`, `forge`, `cosmetics`, `prestige`. FINDING: `menu_sub_state_name = "talents"`
selects the Talents layout of HeroView — confirming gut's entry lands on Talents by design of
its own transition params, not by any engine quirk.

**A4. Grep the keep interaction pedestals in `interactions.lua`.**
DONE. `characters_access` (`interactions.lua:2312-2320`) fires
`handle_transition("character_selection_force", { menu_state_name = "character", use_fade = true })`.
`loadout_access` (2245-2254) fires `character_selection_force` with `menu_state_name = "loadouts"`.
`cosmetics_access` (2267-2277) and `loot_access` (2290-2299) fire `hero_view_force`. FINDING:
the exact call gut should copy for hero/career pick is the `characters_access` body.

**A5. Read the career-swap call chain in `CharacterSelectionStateCharacter`.**
DONE. The Select button (`character_selection_state_character.lua:1494-1510`) requires an
active `Network.game_session()` (1503-1507), then calls
`_change_profile(self._selected_profile_index, self._selected_career_index)` (1509).
`_change_profile` (1602-1615) calls
`self._profile_requester:request_profile(peer_id, 1, profile_name, career_name, force_respawn=true)`.
FINDING: the actual career/hero change is host-mediated via `ProfileRequester` with
`force_respawn = true`; there is no live career setter (matches gut's `_gut_career_swap.lua`
analysis).

**A6. Compare how HeroView loads its preview level vs how CharacterSelectionView does.**
DONE (this is the crash crux). HeroView's character-preview window
(`hero_view/windows/hero_window_character_preview.lua:100-105,163`) calls
`Managers.package:load(self._level_package_name, "HeroWindowCharacterPreview", callback, asynchronous)`
where `_level_package_name = "resource_packages/levels/ui_inventory_preview"`
(`hero_window_character_preview_definitions.lua:225-227`) and gates the viewport mount on
`Managers.package:has_loaded(...)` (line 163). CharacterSelectionView does the opposite: a
whole-file grep for `package` / `Managers.package:load` returns **no matches**, and its
viewport def has **no `level_package_name`**. FINDING: HeroView safely async-loads its level
via the managed package system (which is why gut's inventory feature works mid-mission);
CharacterSelectionView relies on `levels/ui_character_selection` already being resident.

**A7. Read the vanilla debug career-swap tool.**
DONE. `scripts/imgui/imgui_career_debug.lua:194-227` swaps career from an arbitrary context
via `profile_requester:request_profile(player.peer_id, player:local_player_id(), profile_name, career_name, true)`,
resolving the requester through `Managers.state.network.network_server or .network_client`
(`_get_profile_requester`, lines 28-42). FINDING: this is the exact mechanism gut's
`/gut_swap_career` mirrors; it confirms the profile-requester swap works from a
non-CharacterSelectionView context.

**A8. Compare third-party mods (`Vermintide-Mods`, `Loremasters-Armoury`).**
DONE. `Vermintide-Mods/TrueSoloQoL/scripts/mods/TrueSoloQoL/TrueSoloQoL.lua:194-227` calls
`profile_requester:request_profile(..., true)` for both bots and the local player — a shipped
mod precedent for mid-game profile/career swap via ProfileRequester. A repo-wide grep of
`Vermintide-Mods` and `Loremasters-Armoury` for `CharacterSelectionView` / `character_selection_force`
returns **no matches**. FINDING: no known mod opens `CharacterSelectionView` mid-mission; the
established mod pattern is the ProfileRequester call, not the view.

**A9. Grep repo-wide for who loads `resource_packages/levels/ui_character_selection`.**
DONE. `levels/ui_character_selection/world` is referenced ONLY in
`character_selection_view_definitions.lua:385` and `start_menu_view_definitions.lua:191`, and
NO Lua `Managers.package:load` targets `resource_packages/levels/ui_character_selection`.
FINDING: that level bundle is loaded statically as part of the keep/main-menu boot context,
not dynamically at view-open time — so it is almost certainly NOT resident during a live
Adventure mission. This is the concrete basis for the crash concern (see Probe B3 to confirm
empirically).

**A10. In-game avenues not executable from source (recommended next).**
(a) Run gut's already-shipped probes live: `_gut_menu_transition_probe.lua` and
`_gut_keybind_probe.lua` — they already instrument `IngameUI.transition_with_fade` +
`IngameUI.handle_transition`. (b) Decompile a Workshop mod known to change career in-mission
via the `misc-vermintide-mods/_scratch/extract_mod.ps1` pipeline and diff its swap path
against `_gut_career_swap.lua`. (c) Note re VMF: there is no native "register a view" VMF API;
gut authors its own views by hooking `IngameUI.setup_views` (in `gui_tweaker_dev.lua`) and a
class-based view (`_mod_tweaker_view.lua` / `_mod_tweaker_state.lua`, handle
`mod_tweaker_view`). Any custom-picker solution reuses that same pattern.

---

## LIST B — 10 automatic printf DIAGNOSTIC PROBES (no user action beyond playing)

All use the engine global `printf` (the user runs mod logging OFF, so `mod:info` is invisible —
memory `reference_vt2_diagnostics_use_printf_not_modinfo`). Each names a grep-verified symbol.

> **HARD CONSTRAINT (VMF no-duplicate-hook rule):** gut ALREADY hooks
> `IngameUI.transition_with_fade` and `IngameUI.handle_transition` (both `hook_safe`) in
> `_gut_menu_transition_probe.lua:112,127`. A NEW hook on either pair from gut_dev is silently
> dropped. Probes that need those methods MUST extend the bodies in that file, not add new
> registrations.

**B1. Extend the existing `IngameUI.handle_transition` hook to log ALL transitions.**
Symbol: `IngameUI.handle_transition` (already hooked, `_gut_menu_transition_probe.lua:127`).
Prints: `(new_transition, self.current_view after, params.menu_state_name, params.menu_sub_state_name)`
for EVERY transition (drop the Mod-Tweaker-only `_relevant` filter). CONCLUSION MAP: a line
`fired=hero_view_force menu_state=overview menu_sub=talents` when Hero Select is clicked proves
the entry routes to HeroView/talents; a `fired=character_selection_force menu_state=character`
line proves a rewire took effect.

**B2. Wrap `CharacterSelectionView.post_update_on_enter` (full `mod:hook`), printf BEFORE calling original.**
Symbol verified: `character_selection_view.lua:519`. Prints context immediately before the
viewport/level mount: `is_in_inn`, `Managers.state.game_mode:level_key()`, mechanism. CONCLUSION
MAP: if the last log line in a crash dump is this "about to mount" line with a mission level_key,
the fatal is the `levels/ui_character_selection` mount mid-mission (confirms the crash class); if
a matching post-line ("mounted OK") appears, the level was resident and the view is safe.

**B3. (MOST DECISIVE) Read-only `Managers.package:has_loaded` query on each menu open.**
Symbol verified: `Managers.package:has_loaded` (used at `hero_window_character_preview.lua:163`).
On any menu-open transition, `pcall` a query of
`Managers.package:has_loaded("resource_packages/levels/ui_character_selection", "gut_probe")`
and printf the boolean + current `level_key`. CONCLUSION MAP: `true` in a mission = the bundle
is resident and a direct `character_selection_force` is safe (Solution C1 viable); `false` =
must preload (Solution C2) or avoid the view (C4/C5/C6); a pcall error = the package name is not
a loadable resource at all (hard blocker, mirrors the WOC bogenhafen trophy case — must avoid
the view entirely).

**B4. Hook `HeroView._change_screen_by_name` (`hook_safe`).**
Symbol verified: called at `hero_view.lua:508`; defined on HeroView. Prints
`(menu_state_name, menu_sub_state_name)` HeroView lands on. CONCLUSION MAP: `overview / talents`
right after Hero Select fires = confirms the bug from the runtime side (independent of reading
the transition params).

**B5. Hook `CharacterSelectionStateCharacter._change_profile` (`hook_safe`).**
Symbol verified: `character_selection_state_character.lua:1602`. Prints
`(profile_index, career_index, peer_id)`. CONCLUSION MAP: fires only when a swap is actually
committed — proves whether a rewired entry / `/gut_swap_career` reaches the real vanilla swap
call and with what args.

**B6. Hook `ProfileRequester.request_profile` (`hook_safe`) + poll `:result()`.**
Symbol: `ProfileRequester:request_profile` (cited `profile_requester.lua:46-58` in gut's
`_gut_career_swap.lua`; also the imgui + TrueSoloQoL call site). Prints the args on call, then
a follow-up line with `requester:result()` ("success"/"failure"/pending). CONCLUSION MAP:
`failure` = host declined (hero locked / not available for peer) — the swap mechanism works but
was refused; `success` mid-mission = the swap committed live.

**B7. Hook `GameModeAdventure.force_respawn` (`hook_safe`), log resulting spawn position.**
Symbol verified: `game_mode_adventure.lua:283`. On fire, capture `peer_id`; a frame later
printf the new `Managers.player:local_player().player_unit` world position vs the pre-swap
position. CONCLUSION MAP: position == level-start = confirms the teleport-to-start concern in
gut's comment; position == pre-swap location = force_respawn keeps you in place (the concern is
overstated). This is the empirical answer to the teleport question that the source read alone
did NOT settle.

**B8. One-shot probe on mission start: dump `Managers.ui._ingame_ui.views` keys.**
Symbol: `views_function` builds `character_selection` unconditionally (`ingame_ui_settings.lua:737`);
the live table is `Managers.ui._ingame_ui.views` (read in `_gut_menu_transition_probe.lua:95`).
Printf whether `views.character_selection` is non-nil mid-mission. CONCLUSION MAP: non-nil
(expected) = the view OBJECT exists in-mission, so a transition won't fail on "no such view"; it
will proceed to the level mount (isolating the risk to the bundle, per B3).

**B9. Hook `CharacterSelectionView.post_update_on_exit` / `on_exit` (`hook_safe`).**
Symbols verified: `character_selection_view.lua:541` and `:552`. Printf on teardown. CONCLUSION
MAP: paired with B2/B8, a clean exit line after a mid-mission open proves the whole view
lifecycle survives in-mission (not just the mount); no exit line after a logged enter = it
crashed while open.

**B10. One-shot: read `hotkey_hero.disable_for_mechanism` for the current mechanism.**
Symbol verified: `ingame_ui_settings.lua:769-776` (`hotkey_hero.disable_for_mechanism = default_disable_for_mechanism`,
defined line 3). Printf whether vanilla itself would permit the hero hotkey for the live
mechanism/matchmaking state. CONCLUSION MAP: if vanilla disables `hotkey_hero` in the current
in-mission state, that is a strong signal FatShark intends character selection as a keep-only
surface (informs how aggressively gut should gate its own entry).

---

## LIST C — 10 ways to SOLVE it (smallest → most ambitious; verified API, blocker, risk)

**C1. Rewire gut's entry to the correct vanilla transition (one-line change).**
Change `_gut_mission_hero_select.lua:145-149` from `hero_view_force` + `overview`/`talents` to
`Managers.ui:handle_transition("character_selection_force", { menu_state_name = "character", use_fade = true })`
— literally the `characters_access` keep body (`interactions.lua:2312-2320`). API verified. Keeps
the existing keep-gate + Chaos-Wastes bail. BLOCKER: the mid-mission level residency (decided by
Probe B3). RISK: HIGH if fired blind — likely C-level fatal from mounting the non-resident
`levels/ui_character_selection/world` (bypasses the existing `pcall`). Only ship this if B3 says
the bundle is resident in-mission.

**C2. Preload the level package, then fire the guarded transition.**
Before `character_selection_force`, call
`Managers.package:load("resource_packages/levels/ui_character_selection", "gut_hero_select", callback, true)`
and only transition once `Managers.package:has_loaded(...)` is true — mirroring
`hero_window_character_preview.lua:100-179`. API verified. BLOCKER: only works if that path is a
real loadable `resource_package` (A9 found no Lua loader, so it may be boot-bundle-only — verify
with B3's pcall result). RISK: MEDIUM; if the package name is not loadable, `Managers.package:load`
on a non-resident package hard-crashes (memory `reference_vt2_la_package_force_load_crash` +
`reference_vt2_package_load_needs_package_not_unit_path`). Confirm existence first.

**C3. Keep the crash-safe Talents fallback; add an explicit career-swap action to it.**
Leave the entry on HeroView `talents` (already shipped, proven safe), and expose the
ProfileRequester swap (the `/gut_swap_career` path, imgui pattern) as the actual
career-change mechanism from there. Avoids `CharacterSelectionView` entirely. API verified
(`_gut_career_swap.lua`; `imgui_career_debug.lua:194-227`). **How `/gut_swap_career` relates to
the vanilla confirm:** it is a faithful replica of what `CharacterSelectionStateCharacter` does
when you press "Select" — the vanilla confirm calls `_change_profile` → `_profile_requester:request_profile(peer_id, 1, profile_name, career_name, force_respawn=true)`
(`character_selection_state_character.lua:1509,1602-1610`), and `/gut_swap_career` calls the
identical `requester:request_profile(peer_id, local_player_id, hero_name, career_name, true)`
(`_gut_career_swap.lua:192`) with the requester resolved the same way (via
`Managers.state.network.network_server or .network_client`). The only thing gut's command drops
is the surrounding VIEW (the grid, the preview world, the input blocking). So C3 = "vanilla
confirm without the crash-prone view." BLOCKER: force_respawn teleport/desync (Probe B7
quantifies it). RISK: MEDIUM.

**C4. Author a gut HeroView career-picker window that reuses the already-resident inventory-preview world.**
HeroView "overview" already mounts `levels/ui_inventory_preview/world` safely mid-mission
(proven by gut's inventory feature). Inject a custom window into `HeroViewStateOverview`'s
`window_layouts` (`hero_view_state_overview_definitions.lua:222-276`) that lists the current
hero's career portraits; on click, call `request_profile`. Piggybacks the resident world instead
of `ui_character_selection`. BLOCKER: HeroViewStateOverview window plumbing + layout injection.
RISK: MEDIUM-HIGH (UI wiring), but no new level bundle and no keep-only world.

**C5. Revive the dead `_change_career` in-place-respawn pattern.**
`CharacterSelectionStateCharacter._change_career` (`character_selection_state_character.lua:1617-1644`)
plus its `post_update` completion (1116-1126) despawn via `Managers.state.spawn:delayed_despawn(player)`,
capture `POSITION_LOOKUP[player_unit]` (current position), resync loadout, and respawn AT THE
CURRENT POSITION — no level-start teleport. This function is **dead code** (repo-wide grep: only
the definition, zero call sites), i.e. a latent engine facility. Reconstruct it in gut for a
same-hero career change. BLOCKER: dead/untested path; the 1-frame despawn window is the
POSITION_LOOKUP-nil crash class (memory `reference_vt2_ai_takeover_despawn_poslookup_crash`);
needs host mediation for clients. RISK: HIGH (engine-state surgery) but the best UX if it holds.

**C6. Build a fully mod-drawn gut career-picker view.**
Reuse gut's own view infrastructure (`_mod_tweaker_view.lua` / `_mod_tweaker_state.lua`, handle
`mod_tweaker_view`, injected via `IngameUI.setup_views`) to draw a grid of the current hero's 4
careers on a borrowed renderer; click → `request_profile`. No `ui_character_selection` world at
all. BLOCKER: must respect the `create_screen_gui` missing-material guard (memory
`reference_vt2_create_screen_gui_missing_material_crash`) and the DLC gate for locked careers
(CLAUDE.md "DLC Ownership Gate"). RISK: MEDIUM; most control, most UI work.

**C7. Transition to native CharacterSelectionView but intercept the world mount.**
Fire `character_selection_force`, but `mod:hook` `CharacterSelectionView.post_update_on_enter`
(`:519`) to rewrite the viewport widget's `level_name` to the resident
`levels/ui_inventory_preview/world` (or skip the viewport pass) so it never mounts the keep-only
level. BLOCKER: the character-model preview/camera assumes the `ui_character_selection` world;
state machine may key off `world_name = "inventory_preview"` (defs :388) and collide with other
previewers. RISK: HIGH (hacky, preview likely breaks).

**C8. request_profile swap + immediate position restore.**
Fire `request_profile(force_respawn=true)`, then on the respawn hook, teleport the new unit back
to the saved pre-swap position (papering over the level-start teleport without reviving
`_change_career`). BLOCKER: the despawn/respawn window POSITION_LOOKUP-nil crash class; MP desync
if forced locally. RISK: HIGH.

**C9. Host-authoritative, party-synced swap.**
Gate the swap through the host: honor the `Network.game_session()` requirement
(`character_selection_state_character.lua:1503-1510`), route client requests through
`rpc_request_profile` (per `_gut_career_swap.lua`'s documented path), and let
`profile_synchronizer` resync all peers. BLOCKER: matchmaking `hero_is_locked` /
`profile_available_for_peer` may refuse; clients cannot self-swap without host mediation. RISK:
HIGH; correctness-critical for multiplayer.

**C10. Full mid-mission hero/career surface = C6 + C5 + C9 combined (the "done right" endpoint).**
A gut-owned picker view (C6) that swaps career in place at the current position (C5) with full
peer sync and DLC gating (C9), never touching `CharacterSelectionView` or its keep-only world.
This is the complete, correct feature the issue ultimately wants. RISK: HIGHEST effort; the
endpoint to build toward once B3/B7 have settled the residency and teleport questions.

---

## Recommended first steps

1. **Ship Probe B3** (read-only `Managers.package:has_loaded` on `resource_packages/levels/ui_character_selection`,
   extended into the existing `_gut_menu_transition_probe.lua` alongside B1). It is the single
   decisive, zero-risk measurement: it tells you in one play session whether the direct rewire
   (C1) is safe, whether a preload (C2) is needed, or whether the view must be avoided entirely
   (C4/C5/C6). Pair it with B7 to answer the teleport question.
2. **If B3 says the bundle is resident in-mission:** ship C1 (the one-line rewire to
   `character_selection_force` / `menu_state_name = "character"`), keeping the existing keep-gate
   and Chaos-Wastes bail.
3. **If B3 says not resident:** default to C4 (reuse HeroView's resident inventory-preview world
   for a gut career-picker window) as the crash-free path, with C10 as the long-term endpoint.
