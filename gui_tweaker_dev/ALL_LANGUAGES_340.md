# Issue 340: all-language glyph support

## Current decision boundary

Square blocks in chat and player names are missing glyphs in the active font
atlas, not missing localization strings. The standalone Workshop mod **Support
All Languages** (`3232229691`) changes eight entries in the global `Fonts` table
from `materials/fonts/arial` to `fonts/ArialUnicodeMS`.

That target is not a vanilla Vermintide 2 material. It is supplied by the
standalone mod's 32,583,136-byte compiled bundle. The asset is based on
Microsoft's Arial Unicode MS, so this repository must not copy or redistribute
it. Redirecting the font table without an owned atlas would break text rendering.

The bounded present-day solution is therefore to use the standalone mod. A
future native Tweaker implementation requires an independently built Stingray
font resource from a redistributable font family (for example an OFL family),
plus the resulting roughly 25 MB resident-memory cost.

## Diagnostics

Run `/gut_all_languages_status`. It reads, but never changes, the exact eight
font rows used by the standalone implementation and reports one of:

- `unicode_active`: all eight rows use the Unicode atlas;
- `partial_swap`: only some rows were redirected;
- `font_rows_missing`: one or more expected engine rows are unavailable;
- `vanilla_font_active`: all rows still use the vanilla Arial material;
- `custom_provider_active`: all rows use another provider;
- `mixed_provider`: the rows disagree across vanilla/custom providers.

The same command prints six bounded visual samples to local chat: Latin,
Greek, Cyrillic, Japanese, Chinese, and Korean. Each line must render as letters,
not square blocks. It also logs a privacy-preserving UTF-8 report for every
human player name: byte count, code-point count, non-ASCII count, and validity,
but never the name itself. This distinguishes intact name/chat bytes plus a
missing glyph atlas from malformed input data.

If the standalone mod reports enabled but the state is not `unicode_active`,
capture the command output and the current game log. This is solo/local-render
diagnostics; no co-op participant is required.

## Source evidence

- Vanilla `scripts/ui/ui_fonts.lua:6-84`: the eight entries use
  `materials/fonts/arial`.
- Vanilla `scripts/ui/views/chat_gui.lua:331-385`: received sender and message
  strings are copied directly into the chat widget; no language translation or
  glyph substitution occurs in that path.
- Vanilla `scripts/ui/views/chat_gui.lua:705-822`: chat input/recalled messages
  use `KeystrokeHelper._build_utf8_table` and `UTF8Utils.string_length`, proving
  the string path is UTF-8-aware before rendering.
- Vanilla `scripts/managers/player/player_manager.lua:481-487` and
  `scripts/managers/player/remote_player.lua:151-195`: the human roster and
  `player:name()` expose the exact strings diagnosed by the command.
- Extracted standalone `support-all-languages.lua:1-43`: its enable callback
  assigns `fonts/ArialUnicodeMS` to element 1 of those entries and restores the
  captured defaults on disable.
- Extract log: the standalone `.mod_bundle` is 32,583,136 bytes; its Lua and
  manifest files are only a few hundred bytes.
