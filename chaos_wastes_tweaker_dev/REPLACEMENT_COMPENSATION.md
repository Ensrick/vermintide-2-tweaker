# Replacement-player compensation (#465)

## Behavior

`Replacement Player Compensation` is host-controlled and enabled by default.

- When a human leaves an active pilgrimage, CT snapshots that player's granted
  power-ups, persistent buffs, Pilgrim's Coin, and serialized melee/ranged Deus
  weapons. The next replacement bot using that profile receives the snapshot.
- When a human joins and vanilla selects a bot to remove, CT copies the selected
bot's power-ups, persistent buffs, and Deus weapons to the incoming player's
profile row. The incoming player's Pilgrim's Coin is set to the host's current
balance.
- If vanilla falls back to removing a bot with a different profile or career, CT
  leaves the incoming player's state unchanged. Serialized Deus weapons are
  career-specific, so cross-career copying would be unsafe.
- The copied profile and peer rows are marked initialized. This makes the joiner's
  later vanilla initial-setup RPC a no-op instead of overwriting the handoff.
- Spawn data is rebuilt once after a bot-to-human handoff, before the player is
  spawned, so their first visible loadout consumes the compensated state.

## Engine boundary

Vanilla stores progression in `DeusRunState` under peer/local-player/profile/career
keys. `GameModeDeus.player_left_game_session` is the last reliable point at which a
departing human's keyed state can be captured. `GameModeDeus._add_bot` and
`GameModeDeus.remove_bot` are the exact bot creation/removal boundaries. The latter
returns the actual bot selected for the joining human, so no heuristic player match
is required.

The handoff writes existing vanilla SharedState fields. It sends no custom RPCs,
does not poll per frame, and caps diagnostics at 32 lines per run (`[ct:465]`).
Cloning is bounded to six table levels and 256 entries per snapshot.

## Wire safety

Before a snapshot is written, CT checks the existing peer-parity beacon. When parity
is not positively proven, CT-owned power-up and persistent-buff identifiers are
filtered from that copy. Vanilla progression still transfers. This prevents a late
joiner without CT from receiving an unknown network lookup index.

## Co-op verification

1. Host and client enable CT v0.7.277-dev and leave Replacement Player Compensation
   enabled. Begin a Chaos Wastes run.
2. Give the client at least two visible boons, spend or collect coins so their balance
   differs from the host, and upgrade or swap both weapon slots. Record both rarities.
3. Client disconnects. Confirm the same-profile replacement bot has the client's
   boons and both weapon tiers; the log must contain one `human->bot` line.
4. Continue playing, grant the bot another boon or weapon upgrade, then let the client
   reconnect. Confirm the returning player receives the bot's current boons and both
   weapons, while their coin balance exactly matches the host. Require one
   `bot->human` line and no `parity_filtered` entries when both peers run CT.
5. Repeat with the setting disabled. The vanilla fresh-state behavior must remain.
6. Run `/ct_regression_test` and require `replacement_player_compensation_installed`
   to pass.
