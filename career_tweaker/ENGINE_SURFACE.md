# career_tweaker - engine contact surface

What vanilla VT2/Stingray does at every seam `crt` touches, and why the mod is
there. This is the per-mod companion to the subsystem set in `docs/engine/`
(read `docs/engine/README.md` for house style). It does **not** re-explain a
subsystem the engine docs own - it names the seam, cites the vanilla behavior,
and links out. Decompile paths are relative to
`C:\Users\danjo\source\repos\Vermintide-2-Source-Code`; `crt` line numbers are
`career_tweaker.lua` unless a module file is named. `§N` = a `docs/BUG_CLASSES.md`
class; `#N` / "issue N" = a GitHub issue. Grep-verified 2026-07-12 against the
decompile.

`crt` does two things to the engine: it makes a character's level/career-unlock
state *appear* higher than the backend records (progression overrides), and it
swaps or reworks careers' talents, abilities and passives at runtime (the balance
catalog). The second job puts mod-registered buff names onto vanilla NETWORKED
buff paths, which is the mod's one wire-safety exposure (issue 425 / issue 371).

## Hook table

31 registrations (`tools/mod-lint/lint-mod.ps1 -Mod career_tweaker`
PASS = one hook per (Class, method) mod-wide), grouped into 5 rows-of-concern.
`[hook]` = full wrapper (`mod:hook`, can rewrite args/returns); `[safe]` =
`mod:hook_safe` (post-callback, no override); `[tbl]` = table-form hook
(class/helper table passed by reference, immediate resolution, nil-guarded). The
issue-425 peer-parity beacon (`_lib_peer_parity.lua`) adds NO hooks - it POLLS
`Managers.player:human_players()`, deliberately (see subsystem note).

### Progression: XP level + career unlock (owner doc: `docs/engine/11`)

| Class.method (kind) | Vanilla behavior at the seam | Why crt hooks it | Trap / invariant |
|---|---|---|---|
| `ExperienceSettings.get_experience` [hook] `:211` | The single funnel every level/XP read passes through: inventory badge, character-select tile, mission-spawn network field, host hero-level compute [src: `scripts/settings/experience_settings.lua:119`, callers `:83`/`:102`/`:197`] | Report the cumulative XP for the chosen `level_override_<hero>` so the whole DISPLAY pipeline computes a consistent level (`:211`) | Keyed on `hero_name` = per-CHARACTER (display_name), so all 4 careers under a hero share the override. DISPLAY only - the functional gate reads a different path (next row) |
| `PlayFabMirrorAdventure` / `PlayFabMirrorDedicated` / `PlayFabMirrorBase` `.get_read_only_data` [hook,tbl] `:254-256` (loop) | Returns the backend mirror's stored `<hero>_experience` string; the FUNCTIONAL talent-unlock gate reads this, not `get_experience` [src: `backend_interface_talents_playfab.lua` `_validate_talents:234` reads the mirror -> `ExperienceSettings.get_level` -> strips `career_talents[i]` past the level] | Override the mirror's `<hero>_experience` read too, so the display override actually lifts talent/feature unlocks (`_mirror_experience_override`, `:238`) | MUST hook all THREE concrete classes: `class()` COPIES methods into subclasses at load (`docs/engine/01`; CLAUDE.md "HOOK THE DERIVED CLASS"), so hooking only `PlayFabMirrorBase` never fires on the live `PlayFabMirrorAdventure`. Preserve stored TYPE (values are strings). Read-only, never writes to PlayFab (`docs/engine/11`) |
| `ProgressionUnlocks.is_unlocked_for_profile` [hook] `:289` | The LEVEL gate for a career; vanilla already short-circuits `true` on the dev flag `Development.parameter("unlock_all_careers")` at the top [src: `scripts/settings/progression_unlocks.lua:205-208`] | Return `true` when `unlock_all_careers` is on - unlock owned careers past their level requirement (`:289`) | The upstream DLC gate (`career:is_dlc_unlocked`) runs BEFORE this, so unowned-DLC careers stay locked (CLAUDE.md "DLC Ownership Gate"). Host's join-time check uses the same function, so a crt host won't reject its own picks; a non-crt client joining a normal host is still vanilla-gated |

### Career-select / talent UI refresh (owner doc: `docs/engine/09`)

| Class.method (kind) | Vanilla behavior | Why crt hooks it | Trap / invariant |
|---|---|---|---|
| `HeroWindowCharacterSummary.on_enter` / `on_exit` [safe] `:330`/`:333` | The career-select window; `_setup_hero_selection_widgets` bakes each career's `content.locked` ONCE at populate, from the hero level [src: `scripts/ui/views/hero_view/windows/hero_window_character_summary.lua`, `[unverified]` exact line] | Track the live window instance so a `level_override_*` / `unlock_all_careers` change can re-run its tile setup (stale-tile fix, `refresh_career_unlock_ui` `:336`) | `pcall` the refresh: the window may be mid-teardown between a late `on_exit` and the setting-change call |
| `HeroWindowTalents.on_enter` / `on_exit` [safe/full] `_crt_talent_swap.lua` | On enter, vanilla clones the backend's selected talent rows (`hero_window_talents.lua:106-115`). On exit it unconditionally persists those rows and calls `talents_changed()` plus ammo-buff reapply (`:53-74`), even if no row changed. | Track the open desktop picker for swap refresh and snapshot its rows. An identical close performs only animator teardown, preserving accumulated talent buffs (#283); a changed close delegates fully to vanilla. | The full exit hook is intentionally bounded to the source-audited no-change branch. Missing/invalid snapshots fail open to vanilla. One registration per method. |
| `HeroWindowTalentsConsole.on_enter` / `on_exit` [safe/full] `_crt_talent_swap.lua` | Controller talent picker has the same unconditional persistence/reapply close path (`hero_window_talents_console.lua:67-88`). | Apply the same #283 snapshot guard so input mode does not change gameplay behavior. | Distinct engine class. Changed rows always delegate; the no-op branch retains vanilla's `ui_animator = nil` teardown. |

### Career ability / activated-cooldown (crash history) (owner doc: `docs/engine/10`)

| Class.method (kind) | Vanilla behavior | Why crt hooks it | Trap / invariant |
|---|---|---|---|
| `CareerExtension.current_ability_cooldown` [hook] `:316` | Returns `(cooldown, max_cooldown)` for an ability; the ult-activate path and the HUD cooldown bar both consume it [src: `scripts/unit_extensions/default_player_unit/careers/career_extension.lua:673`] | Nil-guard: live-swapping a career's `activated_ability` desyncs the spawned extension's `_abilities`/cooldown from the mutated `CareerSettings`, so the next ult reads nil and the engine crashes at `apply_buffs_to_value(nil, "activated_cooldown")` (`:316`, fix 2026-06-21) | `pcall` (catches both the nil-return site and the tail at `career_extension.lua` line ~698) AND preserve BOTH returns - dropping the 2nd is the multi-return-collapse gotcha (`docs/VMF_RECIPES.md` §2). Fallback `(0, 1)`: ready + no divide-by-zero |
| `CareerExtension.start_activated_ability_cooldown` [safe] `career_tweaker_balance.lua:3679` | Fires at the START of an ability's flow, sets the cooldown [src: `career_extension.lua:349`] | SINGLE consolidation point for two reworks: Foot Knight Battering Ram cooldown refund (`reduce_activated_ability_cooldown_percent`, `career_extension.lua:443`) and the BH Double-Shotted 3s ranged buff | CONSOLIDATED - a 2nd `hook_safe` on this pair silently shadowed the BH branch in v0.2.27->v0.2.32 ("Attempting to rehook active hook" at load). Add new gated branches to the body, never a 2nd hook (`docs/VMF_RECIPES.md` §1) |
| `CareerAbilityWHZealot._run_ability` [safe] `career_tweaker_balance.lua:3572` | Fires the Zealot Holy Fervour ability (buffs + lunge) [src: `scripts/unit_extensions/default_player_unit/careers/career_ability_wh_zealot.lua`, `[unverified]` exact line] | On the green->THP rework, move current permanent HP into temp HP via `PlayerUnitHealthExtension:convert_to_temp` after vanilla fires (`:3572`) | `convert_to_temp` self-routes: server mutates GameSession, client sends `rpc_request_convert_temp`; server clamps `math.min(current, amount)` so read-back permanent is safe |
| `CareerAbilityBWUnchained._run_ability` [hook] `career_tweaker_balance.lua:3973` | Fires the Unchained ult, which calls `overcharge_extension:reset()` [src: `scripts/unit_extensions/default_player_unit/careers/career_ability_bw_unchained.lua`, `[unverified]` exact line] | Two reworks on one hook (distinct class from the Zealot hook, no collision): capture overcharge before `func`, restore 75% after (vent 25% only); add the max-US burst buff (`:3973`) | Full `[hook]` (not safe) because it must read overcharge BEFORE vanilla resets it and restore AFTER; both branches gate on their own `mod:get` per call |
| `ActionCareerDREngineer.client_owner_start_action` [safe] `career_tweaker_balance.lua:3789` | Minigun action start sets `_current_rps = _initial_rps` and lerps to `_max_rps` (spinup) [src: `scripts/settings/dlcs/cog/action_career_dr_engineer.lua`; base `scripts/unit_extensions/weapons/actions/action_minigun.lua`] | Gromril Plated Shot rework: force `_current_rps = _max_rps` at start so first shot is full-rate (`:3789`) | `hook_safe` lands AFTER vanilla sets the lerp values so the overwrite wins; gated on the Gromril talent being equipped |
| `ActionCareerDREngineerSpin.client_owner_start_action` [safe] `career_tweaker_balance.lua:3804` | The visual-spinup action for the minigun windup [src: `scripts/settings/dlcs/cog/action_career_dr_engineer_spin.lua`] | Bypass the visual spinup too so the windup anim matches the forced fire rate (`:3804`) | Distinct class from the row above (separate action), so no hook collision |

### Balance reworks: crit / parry / talent text (local) (owner doc: `docs/engine/10`)

| Class.method (kind) | Vanilla behavior | Why crt hooks it | Trap / invariant |
|---|---|---|---|
| `TalentExtension.has_talent_perk` [hook] `career_tweaker_balance.lua:3195` | Returns whether a perk is present; `no_random_crits` short-circuits the crit roll to false [src: `scripts/unit_extensions/default_player_unit/talents/talent_extension.lua:259`] | Per-career suppression of `no_random_crits` for the Zealot Smite / Merc Hellborg reworks, keyed on `self._career_name` so one career's setting doesn't lift the other's (`:3195`) | Re-reads `mod:get` every call (live toggle); each rework only suppresses for its own career |
| `ActionUtils.get_critical_strike_chance` [hook,tbl] `career_tweaker_balance.lua:3222` | Computes final crit chance after vanilla buffs [src: `scripts/helpers/action_utils.lua:735`] | Subtract the Hellborg crit penalty (the has_talent_perk hook lifts the hard-zero; this supplies the trade-off) (`:3222`) | Table-form (`ActionUtils` is a plain helper table) - guard `if ActionUtils and ActionUtils.get_critical_strike_chance` for load order |
| `_G.Localize` [hook] `career_tweaker_balance.lua:3500` | Global loc-key -> string lookup; VT2 re-feeds the result through `string.format` with the talent's `description_values` | SINGLE consolidation point supplying rewritten talent titles/descriptions for every active rework (keyed by `<talent>_desc` / `<talent>_name`) (`:3500`) | Literal `%` MUST be `%%` (else "[Invalid String Format]"). Only ONE `_G.Localize` hook allowed - a 2nd shadows (CLAUDE.md NON-NEGOTIABLE 8). VMF `_localization.lua` is NOT in global `Localize`, so talent text must come through here (`TALENT_TEXT_RENDERING.md`) |
| `ActionBlock.client_owner_start_action` [safe] `career_tweaker_balance.lua:3532` | Sets `status_extension.timed_block = t + 0.5` (parry window) [src: `scripts/unit_extensions/weapons/actions/action_block.lua`, `[unverified]` exact line] | Extend the parry window to 1.0s for the WHC / GK Virtue-of-Discipline reworks (`:3532`) | `hook_safe` overwrite lands last. Note `ActionBlock` uses `self._status_extension` (underscore) - the next row does not |
| `ActionMeleeStart.client_owner_post_update` [safe] `career_tweaker_balance.lua:3546` | Charge-block sets `status_extension.timed_block = t + 0.5` each tick [src: `scripts/unit_extensions/weapons/actions/action_melee_start.lua`, `[unverified]` exact line] | Same parry-window extension on the charge-block path (`:3546`) | `ActionMeleeStart` inherits `ActionDummy` and stores `self.status_extension` (NO underscore) - opposite of `ActionBlock` |
| `TalentExtension.apply_buffs_from_talents` [safe] `career_tweaker_balance.lua:3840` | Vanilla applies a career's talent buffs after rolling them out [src: `scripts/unit_extensions/default_player_unit/talents/talent_extension.lua:78`] | Universal Mainstay rework: add `crt_mainstay_universal_stagger` to every player regardless of career/talent (`:3840`) | Checks the pre-registered stub's `_crt_pending` flag (not nil) to detect "toggle not applied"; guards `has_buff_type` to avoid re-adding |

### Damage / overcharge / wire safety (per-hit, host-authoritative, wire-visible)

| Class.method (kind) | Vanilla behavior | Why crt hooks it | Trap / invariant |
|---|---|---|---|
| `DamageUtils.apply_buffs_to_damage` [hook,tbl] `career_tweaker_armor_overcharge.lua` | The single chokepoint for gromril consumption and Unchained overcharge-on-damage conversion [src: `scripts/helpers/damage_utils.lua:2134`; gromril `:2335-2345`, overcharge `:2196-2224`] | Temporarily shim the victim's `be.has_buff_type` (hide the gromril marker) or `be.apply_buffs_to_value` (no-op `damage_taken_to_overcharge`) for exempt hits, then restore | Table-form (`DamageUtils` plain table). Host-authoritative. `pcall` + unconditional restore of both shims even if `func` raises; capture all 3 returns (`docs/VMF_RECIPES.md` §2). Fast early-out when all five overcharge/armor toggles are off |
| `PlayerUnitHealthExtension.add_damage` [hook,tbl] `career_tweaker_armor_overcharge.lua` | Applies damage to a player and fires `on_damage_taken` with only attacker, amount, and damage type [src: `scripts/unit_extensions/default_player_unit/player_unit_health_extension.lua:702-703`]. The full method still has `damage_source_name`, required to distinguish Ratling projectiles (`projectile_system.lua:947,994`; Ratling passes its breed name in `bt_ratling_gunner_shoot_action.lua:603`). | Preserve Necromancer Cursed Armor on #334 chip ticks and publish a synchronous full-context record so Focused Spirit can ignore DoT/gas/warpfire/Ratling damage. Under #472's opt-in rework, its proc removes one stack and refreshes the vanilla ten-second cooldown. | One consolidated full 18-parameter hook; no second registration. Both transient context fields are save/restored after `pcall`. Focused Spirit reuses vanilla buff names, so no NetworkLookup/RPC schema expansion. |
| `BuffSystem.hot_join_sync` [hook] `career_tweaker_balance.lua:4102` | Replays EVERY `server_controlled_buffs` entry to a joining peer via `rpc_add_buff`, encoding `NetworkLookup.buff_templates[name]` [src: `scripts/entity_system/systems/buff/buff_system.lua:66`, encode at `:87`; `rpc_add_buff` decode `:417`] | Sender-side, UNCONDITIONAL: hide `crt_*` (and mod-registered-name) entries from the ONE replay pass so a non-crt joiner never decodes a modded index and fatals (`:4102`, issue 425) | Wire safety is never toggle-gated (memory `reference_vt2_wire_safety_never_toggle_gated`; `docs/engine/03` §31). The replay fires during the join handshake BEFORE any parity ack can exist, so no roster gate can win that race - filter is the only fix. `pcall` the wrapped sync, restore stashed entries unconditionally, rethrow to preserve vanilla failure semantics |

### Disabler/dodge diagnostics (observation only)

| Class.method (kind) | Vanilla behavior | Why crt hooks it | Trap / invariant |
|---|---|---|---|
| `PlayerCharacterStateDodging.on_enter` / `.on_exit` [safe] `_crt_bardin_disabler_probe.lua` | Starts/ends the shared per-unit dodge state and networked `dodging` flag [src: `player_character_state_dodging.lua:38-93`] | #440 retain start/end time and position so later disabler resolution can report actual phase, elapsed time and displacement | Weak-key records; only dodges begun within 25m of a disabler emit a bounded local row. This supplies client-owned timing while the host owns AI resolution, without RPC traffic or status writes |
| `BTPackMasterAttackAction.attack_success` [safe] / `BTCorruptorGrabAction.grab_player` [hook] / `BTCrazyJumpAction.leave` [hook] `_crt_bardin_disabler_probe.lua` | Resolve Packmaster from dodge flag+angle/distance+LOS (`bt_pack_master_attack_action.lua:108-139`); Lifeleech from tracked dodge/projectile geometry+LOS (`bt_corruptor_grab_action.lua:108-121,183-238`); Gutter from root+0.2 trajectory, 1m trigger overlap and neck snap (`bt_prepare_for_crazy_jump_action.lua:188-219`; `bt_crazy_jump_action.lua:163-205,244-292,413-471`) | #440 emit bounded comparative outcome rows for Bardin and controls | Exactly 16 rows per disabler kind; full wrappers delegate once and preserve the vanilla return. No target/status/action mutation; first-person height is presentation-only and not consumed here |

## Subsystem notes (how the vanilla flow runs end-to-end, for crt's cases)

Each note is the minimum needed to read the hooks above; the owning `docs/engine`
doc carries the full architecture.

### Level/XP override: display vs functional gate (owner: `docs/engine/11`)

VT2 has TWO independent level reads. DISPLAY (badge, tile, network field) funnels
through `ExperienceSettings.get_experience(hero_name)`
[src: `experience_settings.lua:119`]. The FUNCTIONAL talent-unlock gate does NOT:
`BackendInterfaceTalentsPlayfab._validate_talents` reads
`self._backend_mirror:get_read_only_data(profile.."_experience")`
[src: `backend_interface_talents_playfab.lua:234`], derives the level, and zeroes
any `career_talents[i]` whose `ProgressionUnlocks.is_unlocked("talent_point_"..i, level)`
is false. So overriding only `get_experience` (v0.3.20-dev's first attempt) showed
a character at the override level but STILL stripped its talents. The fix hooks the
mirror read on all three concrete `PlayFabMirror*` classes (the `class()`-copy
caveat, `docs/engine/01`) plus `is_unlocked_for_profile` for the unlock-all path.
All reads, never a write - no XP persists in modded realm and the exposure matches
the display hook.

### Career reworks: hook vs table-mutation (owner: `docs/engine/10`)

The balance catalog reaches the engine three ways, only one of which is a
`mod:hook`. (1) **BuffTemplates field patching** - `apply_balance_mods` writes
`template.buffs[1][field] = value` directly into the global `BuffTemplates`,
saving originals for restore (`career_tweaker_balance.lua:4000`). (2) **ProcFunctions
repointing** - proc bodies are resolved BY NAME from the writable global
`ProcFunctions` at fire time [src: `buff_extension.lua:1351`] and snapshotted into
`buff.buff_func` at add time [src: `buff_extension.lua:421-423`], so crt either
wraps an existing entry (Salvaged Ammunition, Fires from Ash, Vanhel's) or points a
template's `buff_func` at a crt-owned wrapper (Cursed Armor counter-remover). These
are NOT hooks and do not appear in the table above, but they are engine contact and
follow the same restore discipline. (3) **`mod:hook`** - the 20 table rows, for the
per-frame/per-action seams the data patch can't reach. New reworks that touch a
NETWORKED buff path must additionally route through a `crt_wire_safe_*` wrapper (see
next note). #473 Dance of Blades replaces the talent's buff-name list with one
blocking-dodge driver and one kill driver; the latter grants a paired
`damage_dealt`/`damage_taken` stack through the existing wire-safe add wrapper.
Its two-second stacks set `refresh_durations=false`, so every kill retains its own
expiry rather than refreshing the full stack group.

### Networked buffs + peer parity (owner: `docs/engine/03`; project `project_vt2_cross_peer_wire_safety`)

Nine rework toggles push a mod-registered buff name onto a vanilla NETWORKED buff
path (server-controlled buff drivers, special-kill procs, the tourney WP aura). Each
encodes `NetworkLookup.buff_templates[name]` and sends `rpc_add_buff`; a peer without
crt has no entry at that index, so `BuffSystem.rpc_add_buff` fatals on the strict
`__index` decode [src: `buff_system.lua:417`] - and it fatals in BOTH directions (a
crt client's send is relayed by a non-crt host to every client; a crt host broadcasts
to every non-crt client). This is a GAMEPLAY axis (`docs/engine/03` wire-safety
doctrine): the substitute would change what happens, so it cannot be substituted like
a cosmetic - the feature must go INERT until every peer has crt. That gate is the
`_lib_peer_parity.lua` beacon (issue 371): a VMF-channel presence handshake
(`crt_peer_parity_present`, schema 1) whose ABSENCE of a reply proves a peer lacks
crt. It POLLS `Managers.player:human_players()` rather than hooking
`add_remote_player`/`remove_player`, deliberately - the lib is COPIED into the host
mod, so its hooks would register under crt's id and VMF would drop them if crt already
hooked those methods (`docs/engine/03`; the lib header spells this out). Fail-safe:
inert until positively confirmed; solo counts as parity; any tick error forces
features OFF. The one case the roster gate CANNOT cover is `hot_join_sync`, whose
replay fires before any ack exists - handled by the unconditional sender-side filter
(last hook row). The user's saved setting is never overwritten; a held rework just
stays at vanilla for that apply pass and re-applies when parity re-establishes.

## What the engine will NOT let us do (dead ends, already paid for)

Pulled from `CHANGELOG.md`, `DEVELOPMENT.md` and `docs/BUG_CLASSES.md` - do not
re-discover these.

- **Overriding display XP does not lift talent unlocks.** The functional gate reads
  the backend mirror's raw `<hero>_experience`, not `get_experience`, so a character
  shown at level 35 still had its talents stripped by the real (low) XP until the
  mirror read was ALSO overridden - on all three `PlayFabMirror*` classes, because
  `class()` copies methods at load (v0.3.20-dev; CHANGELOG + CLAUDE.md "HOOK THE
  DERIVED CLASS").
- **Two `hook_safe` on one (Class, method) silently shadow - it cost a whole feature.**
  The BH Double-Shotted damage-doubling branch was dead from v0.2.27 to v0.2.32
  because a second `hook_safe("CareerExtension","start_activated_ability_cooldown")`
  shadowed the first ("Attempting to rehook active hook" at load). Fix: ONE hook per
  pair, gated branches in the body (`career_tweaker_balance.lua:3819-3826`;
  `docs/VMF_RECIPES.md` §1). Same rule killed a would-be 2nd `_G.Localize` hook.
- **A per-call `be.trigger_procs` swap swallows EVERY proc on that event.** The
  original Cursed Armor chip-exemption temporarily replaced the victim's
  `be.trigger_procs` and early-returned on `on_damage_taken` - which also killed every
  OTHER buff's `on_damage_taken` proc for that tick (stacking-DR removers, Numb to
  Pain, Exuberance). The durable fix scopes the exemption to ONE proc via a crt-owned
  `ProcFunctions` wrapper + a per-victim exempt flag, touching no other proc
  (v0.3.56-dev; old defect self-documented at `career_tweaker_armor_overcharge.lua`
  old `:294-296`).
- **`heal_network` / server-authoritative effects fatal on clients.** Fires from Ash's
  THP grant called `DamageUtils.heal_network`, which fasserts "Only server can heal"
  on a client [src: `damage_utils.lua:2636`]; the proc runs on the host for a client's
  kill anyway, so the grant must gate on `Managers.player.is_server` and the client
  instance no-ops (issue 405, § "Only server can heal"). Same class hit ct (#406) and
  is the mandatory grep on any new proc that heals.
- **A modded buff index on a vanilla RPC CTDs every peer without the mod - in both
  directions, and hot-join can't be roster-gated.** See the networked-buffs subsystem
  note; the paid-for lesson is that the fix is unconditional wire safety (substitution
  for cosmetic axes, inert-gate for gameplay axes, sender-side filter for the hot-join
  race), never a menu toggle (issue 425 / issue 371; memory
  `reference_vt2_wire_safety_never_toggle_gated`).
- **Career-select / talent tiles bake `content.locked` ONCE at populate.** Flipping a
  level_override / unlock-all setting while the window is open leaves the tiles stale;
  there is no vanilla "refresh" event, so crt tracks the live window instance via
  on_enter/on_exit and re-runs `_setup_hero_selection_widgets` on the setting change
  (2026-06-21 fix).

## Doc maintenance

Follows `docs/engine/README.md` maintenance rules: if a crt hook moves, a guard is
added, or a cited vanilla line drifts after a game patch, edit the affected row in
the SAME commit. Line numbers are against the 2026-07-12 decompile - match crash
logs by function name, not line. Several UI `on_enter`/`on_exit` targets carry
`[unverified]` exact lines (the class + method are grep-confirmed present; only the
line inside was not pinned this pass) - replace the tag with a citation when next
touched. Section shape (hook table -> subsystem notes -> dead ends) matches
`character_weapon_variants/ENGINE_SURFACE.md`; keep it stable. Reverse index:
`docs/engine/README.md` "Per-mod surface docs".
