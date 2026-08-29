# Scoreboard feature research (#272)

This document fixes the implementation boundary for bringing detailed mission
statistics into Tweaker: GUI. It is a source-derived plan, not a copy of the
external **Tab Scoreboard** Workshop item (`3595332090`). The installed item
contains compiled bundles and a 546-byte VMF descriptor but no visible source
tree or redistribution license. GUT may interoperate with its public mod id but
must independently implement every feature unless the author supplies a
compatible license.

## Native data path

Vanilla already defines eleven Adventure scoreboard topics: elite, special,
total, melee, and ranged kills; damage taken; total and boss damage; headshots;
saves; and revives (`scripts/helpers/scoreboard_helper.lua:4-187`). The grouped
catalog contains those same eleven names and computes
`num_stats_per_player` from the group rows (`scoreboard_helper.lua:189-218`).
`ScoreboardHelper.get_grouped_topic_statistics` resolves current players and
reads the catalog from `StatisticsDatabase` (`scoreboard_helper.lua:344-436`).
The session-score sender flattens that exact grouped row count, and the receiver
rejects a host payload whose count differs from its local
`ScoreboardHelper.num_stats_per_player`
(`scripts/managers/game_mode/game_mechanism_manager.lua:244-264,1054-1073`).
The GUT extension therefore never appends Aidings or Times Revived to the
vanilla catalog or wire.

The underlying definitions mark every existing scoreboard scalar as
`sync_on_hot_join`, including melee/ranged kills, headshots, revives, aidings,
saves, times revived, total damage, total kills, and damage taken
(`scripts/managers/backend/statistics_definitions.lua:13-42,486-501`). Per-breed
kills are also marked, but per-breed damage is not
(`statistics_definitions.lua:613-629`). That leaves one native presentation gap:
`damage_dealt_bosses` sums per-breed damage and cannot reconstruct damage dealt
before a client joined. During hot join, `StatisticsDatabase` walks marked records and sends
`rpc_sync_statistics_number` (`scripts/managers/backend/statistics_database.lua:225-235`);
the receiver writes the value into the joining peer's local database
(`statistics_database.lua:645-661`). Therefore the first implementation phase
can reuse vanilla transport for ten topics, but must either document or
explicitly synchronize the boss-damage gap.

## UI seams

The hold-Tab view is `IngamePlayerListUI`. Its `update` method owns held/toggled
activation and calls its own draw only while active
(`scripts/ui/views/ingame_player_list_ui_v2.lua:1072-1139`); `_set_active`
owns cursor, input capture, and the `ingame_player_list_enabled` event
(`ingame_player_list_ui_v2.lua:1179-1255`). A GUT statistics page should
therefore compose with this class's active lifecycle, not install a competing
Tab input handler.

The end screen receives `context.players_session_score` and immediately feeds
it to `_setup_player_scores` (`scripts/ui/views/level_end/states/end_view_state_score.lua:51-53`).
That method and `_setup_score_panel` transform the same grouped player data into
the fixed four-column presentation (`end_view_state_score.lua:479-574`). The
native end-screen data shape can be reused, while pagination, visibility, and
sorting should live in a separate GUT presentation policy so Tab and end-screen
views cannot disagree.

## Requested-stat classification

| Requested field | Native status | Implementation consequence |
|---|---|---|
| Ten ordinary native topics | Tracked, grouped, hot-join synced | Reuse the vanilla snapshot directly. |
| Boss damage | Tracked per breed, not hot-join synced | Present locally for full-run peers; add bounded host state before claiming late-join parity. |
| Aidings / times revived | Tracked and hot-join synced, not currently displayed | Safe candidates for the first expanded native page. |
| Times friend healed | Persistent count only (`statistics_definitions.lua:79-82`) | Do not present it as session healing or healing amount. |
| Friendly-fire damage | No player statistic definition | Requires host-authoritative accumulation at the resolved damage boundary. |
| Healing amount | No player statistic definition | Requires a separate authoritative healing transaction boundary. |
| Melee/ranged damage split | Only kills are split; damage is total/per-breed | Requires reliable attack-source classification and accumulation. |

## Phased implementation

1. **Inventory diagnostics (complete in v0.2.260-dev).** Prove the current
   catalog and live snapshot shape with capped `[gut:272]` records.
2. **Native live page (implemented in v0.2.264-dev).** The default-off
   **Expanded Scoreboard** draws all eleven native topics through the
   existing `IngamePlayerListUI._draw` lifecycle. Its pure model is capped to
   four detached player records, offers six deterministic sort choices, and is
   refreshed at most four times per second. It adds no input owner, statistic
   accumulator, RPC, or lookup entry and declines to draw alongside the
   installed external scoreboard. After the live TSV-layout failure, the
   renderer uses an explicit root scenegraph plus one fixed text pass per
   title, header, label, and value cell; row placement no longer depends on
   newline handling inside a large text pass.
3. **Native end-screen page (implemented in v0.2.264-dev).** The same detached
   model renders from `context.players_session_score` after vanilla's
   `EndViewStateScore.draw`; it adds no replacement state or score transport.
4. **Native paging and visibility (implemented in source for #1414).** One
   GUT-owned registry copies the eleven vanilla descriptors and appends
   localized Aidings and Times Revived descriptors. The two extra scalar
   values are read live for held Tab. Normal Adventure context construction
   carries `players_session_score` but does not carry `statistics_db`
   (`state_ingame_running.lua:274-344`); the score state merely assigns that
   absent context field (`end_view_state_score.lua:23-29`). A chained
   StateIngame-exit owner therefore captures only four players by two scalars
   before database teardown, once per mission generation. `GameStateMachine`
   supplies the old state object to mod callbacks before its native transition
   (`game_state_machine.lua:14-21`), providing the still-live database and
   profile synchronizer. The end presenter consumes that detached sidecar
   without touching the native score table or wire. StateLoading carries an
   active end-view wrapper into the next StateIngame through
   `loading_context.level_end_view_wrappers` (`state_loading.lua:1671-1677`;
   `state_ingame.lua:347-380`), so that exact enter preserves the sidecar while
   always clearing the held-Tab cache. An ordinary no-wrapper StateIngame enter
   clears it; nested state notifications remain neutral because
   `StateInGameRunning` is constructed inside `StateIngame.on_enter` and can
   notify before the outer callback (`state_ingame.lua:345-388`;
   `game_state_machine.lua:21-27`). A backwards mission clock independently
   forces a fresh snapshot. Eleven rows
   fit on each of at most four pages; overflow, malformed, and duplicate topics
   are explicit model verdicts. Page and per-topic visibility are persisted VMF
   settings. A hidden saved sort falls back to Player Name without rewriting
   the saved preference. The optional page keybind only advances the setting
   and owns no Tab/update/input hook. Adventure reconnect retention now includes
   both scalar paths within the existing 8-player / 64-path limits.
5. **Host boss-subtotal parity (implemented in source for #1448).** The host
   answers a bounded readiness pull by reading the existing grouped
   `damage_dealt_bosses` entry from
   `ScoreboardHelper.get_grouped_topic_statistics`; it does not hook a damage
   transaction or accumulate a second value. One exact
   `gut_boss_damage_snapshot_v1` VMF channel carries schema `1` request and
   aggregate snapshot envelopes. The requester first forces VMF's presence
   re-handshake, waits 0.4 seconds, and retries at most four sends; the host
   caches and resends the same immutable response for an exact duplicate request
   sequence, so a lost request or response is idempotent even though VMF's pong
   re-fires `on_user_joined`. Pongs cannot rearm a terminal pull, giving each
   pull an absolute four-send cap. Each peer is limited to one response per 0.75
   seconds and one fresh extraction per two seconds; same-generation sequences
   must be contiguous and a mission accepts at most sixteen generations.
   Compatible clients refresh the aggregate rather than sending per-hit traffic.

   The receiver accepts only the current host peer, its current opaque mission
   generation, and the exact pending monotonic sequence. It validates one topic,
   at most four known unique `stats_id` strings, finite non-negative values no
   greater than one billion, 64-byte generation/player strings, dense arrays, a
   1,024-byte encoded payload, and at most eight 144-byte chunks.
   Before every send, the exact eight-argument VMF JSON array is measured and
   rejected above 400 bytes, leaving headroom beneath the native 500-character
   packed-message limit (`docs/VMF_RECIPES.md` sections 3, 3a, and 4). A valid
   row replaces only the matching detached live model cell; absent, expired,
   mixed-version, and no-GUT snapshots keep the usable native value. A sorted
   four-row `stats_id` fingerprint observes human and bot roster changes at a
   0.5-second floor without treating VMF discovery callbacks as physical joins
   or leaves. Clients poll only while the option owns an enabled pull/display;
   hosts begin lazily after an authenticated request, so the default-off feature
   performs no continuous grouped-scoreboard work. A real change rotates the
   client request identity, rejects partial old chunks, and permits one early
   host rebuild without bypassing the send floor.

   The accepted row is copied with #1414's StateIngame-exit sidecar. On the end
   surface only, the model uses `max(valid native final, valid captured host)`;
   cumulative boss damage therefore cannot be lowered by a host snapshot that
   predates the final hit, while a newer captured host row can still repair a
   partial native row. Mission entry/exit, canonical host migration, setting
   disable, and mod teardown retire the relevant transport state. VMF's early
   bot `on_user_left` callback only schedules roster reconciliation. The
   vanilla fixed-count score RPC,
   `StatisticsDefinitions`, and `NetworkLookup` remain untouched.
6. **Other custom statistics.** Add one field family at a time with an
   authoritative owner, bounded wire schema, hot-join state, and two-player
   regression matrix.

The issue remains open after the native presentation slice. Friendly-fire
damage, healing amount, and melee/ranged
damage require separately specified host-authoritative accumulation before they
may appear. Boss damage now has source-only late-join parity through #1448 but
remains unclaimed live behavior until an exact reviewed Dev artifact completes
the issue's Solo-first acceptance. The shared page and visibility policy applies
identically to the Tab and end-screen presenters.
