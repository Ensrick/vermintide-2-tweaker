## CURRENT LIVE TEST

<!-- Pin this comment and unpin every older exact CURRENT LIVE TEST comment. -->

**Build/banner:** v0.0.0-dev, confirm `[mod:LOAD]`
<!-- If the mod has no :LOAD marker, reproduce its whole versioned banner instead: exact banner: [WOC] v0.1.42-dev loaded -->
<!-- Every named build/version/tag pair must match the latest deployed release manifest and its exact source commit. -->
**Topology:** Solo

1. Open the named menu or enter the named game area.
2. Use the localized item or setting name shown in-game.
3. Perform the one action that reproduces or verifies the issue.

**Expected:** State the visible result or bounded log evidence that constitutes a pass.

<!--
Exact player-entered slash commands must be wrapped in backticks and must exist
in the deployed source named above. When a diagnostics-armed card asks for log
evidence, it must name at least one bounded receipt emitted through printf
(directly or through an approved receipt helper); quote its stable prefix
literally, for example `[mod:123] result=`. Do not invent a command or evidence string, cite a stale
version, list an unbound sibling version/tag, or give contradictory manifest IDs.

For co-op only after useful solo work is complete, replace Topology and add:

**Topology:** Co-op (host and one client)
**Solo status:** Passed; only the remote-player result remains.

Then add the coop-required label. Never put internal keys in numbered steps;
an exact player-entered slash command is allowed when wrapped in backticks.
The newest exact card must remain the only pinned exact card on the issue.
-->
