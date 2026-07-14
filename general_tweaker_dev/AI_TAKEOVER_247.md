# Issue #247 — Keep-slot bot takeover

## Outcome

The old conversion path is retired. It removed the human `Player`, party slot,
and synchronized profile before constructing a bot, which created ownerless
units and one-frame teardown races. The replacement preserves those three
authorities for the entire takeover.

## Source-backed lifecycle

1. Admit only a living human on the host, in `adventure`, `deus`, or `weave`,
   with either a free slot or one ordinary native bot that can yield its slot.
2. When vanilla has filled the party, remove one ordinary bot through the
   current mode's native `_remove_bot` method and remember its exact profile,
   career, and slot. Never displace another active takeover bot.
3. Construct one real bot through `GameModeBase._add_bot_to_party`, append it to
   the current mode's native bot roster, and seed its spawning data from the
   owner's live position. [`game_mode_base.lua:79-97`]
4. Keep the human `Player`, profile assignment, and original party slot. Mark
   only its spawning state despawned, enter the same observer camera used by
   death, and call the human player's native unit-despawn method.
   [`camera_system.lua:264-268`; `bulldozer_player.lua:60-83`]
5. On reclaim, remove only the recorded temporary bot, restore the displaced
   native bot to its exact slot, and call the mode's `force_respawn` for the still-present
   human. Adventure, Deus, and Weave each delegate this to their spawning
   component. [`game_mode_adventure.lua:283-292`; `game_mode_deus.lua:440-449`;
   `game_mode_weave.lua:276-285`]

No `PlayerManager.remove_player`, party reassignment, profile unassignment,
locomotion override, custom network lookup, or per-frame RPC is used.

## Network contract

Schema v2 makes the VMF sender authoritative. A payload claiming another peer
or any local player id other than 1 is rejected, and `want_bot` must be an
explicit boolean. The host sends a bounded result
acknowledgement containing its actual active state; the client accepts that
message only from the current host, validates its field types, and silently reconciles its checkbox. The
existing three-attempt handshake queue remains idempotent.

The transaction constructs and registers the temporary bot before touching the
human. It despawns the human before entering observer camera, so a throwing
despawn leaves the camera on the still-live owner. If observer setup then fails,
the temporary bot is removed, any displaced native bot is restored, and native
`force_respawn` rebuilds the owner. Reclaim verifies both removal and respawn
APIs before removing the temporary bot.

## Co-op verification

1. Start an ordinary bot-filled Adventure with host plus one GT client.
2. Client enables Bot Takeover. Confirm the client observes, exactly one
   temporary bot drives the same hero, and host/client remain connected.
3. Client disables it. Confirm only that bot disappears and the client respawns
   with control. Repeat via AFK trigger and input reclaim.
4. Repeat once in Chaos Wastes and once in a Weave.
5. Fill all four slots with humans and enable it. Confirm immediate refusal, no despawn, and
   the client checkbox returns off.
6. Run `/gt_regression_test`; require `issue247_keep_slot_takeover_wired` and the
   existing AI client-send queue checks to pass. Grep `[gt:247]` for one request
   and a converged result per retry series, with no ownership/POSITION_LOOKUP
   error.
