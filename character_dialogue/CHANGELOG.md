# Character Dialogue Changelog

## 0.1.10-dev (2026-08-16) -- automatic audio isolation during previews (#998) [verify-fix]

- New "Isolate Audio During Playback" ON/OFF control at the top of Mod
  Tweaker's Dialogue tab (rendered by the custom tab renderer). While enabled,
  playing a preview mutes the music and sound-effects buses automatically, and
  every termination path restores them: stop, natural completion, replacement
  teardown failures, collapse, view exit, world transition, disabling the
  toggle, and mod disable/unload.
- Isolation is owner-token based: the automatic preview owner composes with
  the manual `/cd_isolate` owner. Volumes mute when the first owner acquires
  and restore only when the last owner releases; pause/resume and line
  replacement hold the token so swaps never flicker.
- Natural-completion polling moved into the frame update, so a line finishing
  with the tab closed still restores volumes; a restore attempted while no
  audio world exists retries each frame until the engine accepts the write.
- API v5: `get_auto_isolation`/`set_auto_isolation`/`auto_isolation_label`.
  `/cd_stop` hardened against stray chat arguments; `/cd_regression_test`
  additionally asserts the ownership arbitration and lifecycle edge tables.

## 0.1.9-dev (2026-07-20) - conversation grouping, transcript search, audio isolation (#605 #998) [untested]

- Browser groups by CONVERSATION (the event stem) instead of by character, and orders each group's lines by their numeric ordinal so an exchange reads in the order the game plays it. Stems sort by topic first, so every hero's version of one conversation lands adjacent: searching `downed_three_times` returns the whole set rather than five scattered entries.
- Search now matches the SPOKEN words as well as the codename. `tuple[2]` is a localization key, so searching "down again, elf?" previously could not match anything; subtitle keys are now resolved to prose once at first Dialogue open and every later query is a plain string find. Codename search is unchanged and still works.
- Page items carry the resolved transcript and the speaker's display name, so a row no longer depends on its header for the character's identity.
- New `Isolate Dialogue Audio` keybind and `/cd_isolate` command: mutes `music_bus_volume` and `sfx_bus_volume` while leaving `voice_bus_volume` untouched, so a line can be auditioned without flying out of the play area to escape ambient sound. Toggling off restores the player's own saved volumes. Bus writes use the same `WwiseWorld.set_global_parameter` path vanilla uses (`scripts/ui/views/options_view.lua:1907-1909`, applied at `:2043`/`:2049`; `scripts/managers/music/music_manager.lua:1019-1025`).
- API is v4: `browser_groups`/`browser_page` are keyed by conversation stem, not speaker.

**Test:** open Mod Tweaker's Dialogue tab. Search `downed_three_times` and confirm each hero's conversation appears as its own group with lines in ordinal order, transcripts visible inline under each codename. Then search a phrase you have heard in game (for example `down again`) and confirm the matching line is found. Press the Isolate Dialogue Audio key in a mission and confirm music and effects mute while a previewed line stays audible, and that pressing again restores your volumes.

## 0.1.7-dev (2026-07-22) - #881 bounded Morris soundbank residency [verify-fix]

- The #927/#940 logs prove silent `pes_morris_*` clicks reach Wwise but return
  playing ID `0`. Bundle inspection then found every reported event ID in one
  bank owned by Fatshark's `resource_packages/dlcs/morris_ingame` package.
- Character Dialogue now loads that one audited package asynchronously on the
  first Morris preview, holds exactly one private
  `character_dialogue_preview` reference while the preview UI owns it, and
  retries only the latest pending click after residency. Stop, collapse, view
  exit, world transition, disable, and unload release the reference.
- The loader never derives package names from arbitrary catalogue text, never
  loads a whole level package, never queues the same reference twice, and
  abandons a missing/stalled load after a bounded 30 seconds.
- Added engine-free mapping, latest-click, timeout, and cleanup regressions;
  `/cd_regression_test` also asserts the audited mapping at runtime.

### Solo verify

In the keep, open **Mod Tweaker > Dialogue > Markus Kruber** and search for
`pes_morris_bardin_song_kruber_13`. Click Play once. The log must show one
`[cd:881] package_queued`, then `package_ready`, followed by
`[character_dialogue:preview] play ... id=<non-zero>`, and the line must be
audible. Stop it, play it again, then leave the Dialogue tab; there must be no
crash, repeated load loop, or package-reference warning. Run
`/cd_regression_test`; failures must be zero.

## 0.1.6-dev (2026-07-19) - #881 diagnostics for silent preview clicks [diag]

- printf every preview play rejection (validation error, missing level audio
  world) - both branches previously returned without any log line.
- printf every auto-stop with elapsed vs duration; near-zero elapsed against a
  real duration flags a non-resident soundbank that accepted the trigger but
  never played media.

## 0.1.4-dev (2026-07-19) - #605 preserve false and nil dialogue states [verify-fix]

- Replaced Lua `and/or` pseudo-ternaries that made `nil` and `false`
  unreachable when collapsing a speaker or disabling a dialogue line.
- Added explicit, testable state transitions for the UI Disabled state and
  `/cd_line ... disable` command path.
- Added regression coverage for close/reopen and enable/disable/default state
  transitions without changing the catalogue or network surface.

**Solo verify:** in Mod Tweaker > Dialogue, open and close a speaker group,
then cycle a line through enabled, disabled, and default. The group must stay
closed and Disabled must remain selected after Apply/reopen/restart.

## 0.1.3-dev (2026-07-16) - #605 [not-started]

- Extended the offline-generated 34,327-event catalogue with Fatshark's
  authored `sound_events_duration` value for every stable Wwise event ID.
- Added one bounded preview snapshot poll using `WwiseWorld.is_playing` and
  `WwiseWorld.get_playing_elapsed`. The engine elapsed value is converted from
  milliseconds to seconds, clamped to the authored duration, frozen while
  paused, and reset on every existing preview cleanup boundary.
- Advanced the Character Dialogue browser API to version 3 so Tweaker: GUI dev
  can render exact active-clip progress without scanning or rebuilding the
  catalogue per frame.

### Solo verify

Open Mod Tweaker > Dialogue and play one resident line. Confirm its triangle
changes to two pause bars and its progress bar advances. Click the same button
to pause; the triangle returns and progress freezes. Click again to resume,
then play another row and confirm the old row resets immediately. Collapse the
character or close the view and confirm playback and progress both reset. Run
`/cd_regression_test`; failures must be zero.

## 0.1.2-dev (2026-07-15) - #605 [verify-fix]

- Replaced the 34,327-option flat dropdown with a Character Dialogue-owned,
  grouped browser API. Heroes use their canonical event prefixes; generated
  source filenames are not trusted as speaker identity because those containers
  can also hold enemy-lord dialogue.
- Excluded the catalogue's one exact `dummy` Wwise sentinel while retaining real
  event names that merely contain that word. All 34,326 playable candidates are
  assigned to a character, NPC, enemy, or fallback group.
- Added bounded 32-row paging, grouping-preserving search, stable event identity,
  and a pure single-owner play/pause/resume/stop state machine.
- Registered the new Dialogue browser control only with Tweaker: GUI dev; stable
  GUI versions cannot accidentally attempt to render the new control.

### Solo verify

Open Mod Tweaker > Dialogue. Expand multiple character sections and confirm only
one stays open. Search by event/source text, then use the same row's state, Play,
and Pause/Resume buttons. Starting a second row must replace the first; collapsing
its character or leaving/closing the view must stop it. Run
`/cd_regression_test`; failures must be zero.

## 0.1.1-dev (2026-07-15) - #605 [verify-fix]

- Load Fatshark's module-local `DialogueQueries` table explicitly before
  installing the natural-selection hook, eliminating the VMF nil-object error
  emitted at startup.

## 0.1.0-dev (2026-07-14) - #605 [verify-fix]

- Added an offline-generated catalogue of 34,327 stable dialogue event IDs from Fatshark's generated dialogue sources.
- Added sparse persistent enable, disable, and default overrides with bounded host-authoritative natural selection.
- Added local play, pause, resume, and stop ownership with cleanup across view/world/mod transitions.
- Added the Mod Tweaker Dialogue tab contract and console fallbacks.
