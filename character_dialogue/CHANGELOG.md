# Character Dialogue Changelog

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
