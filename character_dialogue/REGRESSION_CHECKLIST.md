# Character Dialogue Regression Checklist

- `/cd_regression_test` reports zero failures and 34,327 unique catalogue entries.
- Dialogue tab opens without loading the catalogue before first use.
- Search/select a resident line. Its one media button shows a play triangle,
  becomes two pause bars while playing, and returns to play while paused.
- Open and close the same character header with mouse and controller; closing
  removes its rows and stops any preview owned by that character.
- The active row's progress bar advances from the Wwise playback position,
  freezes while paused, and resets after replacement, stop, or cleanup.
- Leaving Mod Tweaker or changing worlds stops the local preview.
- Disable one line in a multi-line group: it is not selected naturally.
- Cycle one line Default -> Enabled -> Disabled -> Default; all three labels
  and persisted values must be reachable.
- Disable every line in one group: the response is suppressed without a nil-index error.
- Enable a normally filtered line: it becomes eligible while its parent rule remains intact.
- Restart the game: sparse line overrides persist.
