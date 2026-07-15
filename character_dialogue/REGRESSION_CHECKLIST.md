# Character Dialogue Regression Checklist

- `/cd_regression_test` reports zero failures and 34,327 unique catalogue entries.
- Dialogue tab opens without loading the catalogue before first use.
- Search/select a resident line, then Play, Pause/Resume, and Stop.
- Leaving Mod Tweaker or changing worlds stops the local preview.
- Disable one line in a multi-line group: it is not selected naturally.
- Disable every line in one group: the response is suppressed without a nil-index error.
- Enable a normally filtered line: it becomes eligible while its parent rule remains intact.
- Restart the game: sparse line overrides persist.
