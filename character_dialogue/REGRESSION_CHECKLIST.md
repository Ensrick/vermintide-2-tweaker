# Character Dialogue Regression Checklist

- #998: Click Isolate Audio During Playback: Apply enables but no setting/audio
  changes until Apply. Close without Apply, reopen, and confirm the old value.
- Apply ON and OFF while a preview plays; restart and confirm persistence.
  Manual `/cd_isolate` remains independent and exact volumes restore on release.
- GUI `/gut_regression_test` includes `issue998_dialogue_staged_isolation`.
  CD's ownership-only self-check cannot prove GUI staging by itself.

- `/cd_regression_test` reports zero failures and 34,327 unique catalogue entries.
- Dialogue tab opens without loading the catalogue before first use.
- Search/select a resident line. Its one media button shows a play triangle,
  becomes two pause bars while playing, and returns to play while paused.
- Open and close the same character header with mouse and controller; closing
  removes its rows and stops any preview owned by that character.
- The active row's progress bar advances from the Wwise playback position,
  freezes while paused, and resets after replacement, stop, or cleanup.
- Leaving Mod Tweaker or changing worlds stops the local preview.
- From the keep, play `pes_morris_bardin_song_kruber_13`: one `[cd:881]
  package_queued`/`package_ready` pair is followed by a non-zero Wwise playing
  ID and audible dialogue. Repeated clicks keep one package reference; Stop,
  collapse, view exit, world transition, disable, and unload release it.
- While the Morris package is still loading, click two Morris rows. Only the
  latest row plays after residency and the wait cannot exceed 30 seconds.
- Disable one line in a multi-line group: it is not selected naturally.
- Cycle one line Default -> Enabled -> Disabled -> Default; all three labels
  and persisted values must be reachable.
- Disable every line in one group: the response is suppressed without a nil-index error.
- Enable a normally filtered line: it becomes eligible while its parent rule remains intact.
- Restart the game: sparse line overrides persist.
