# Replacement-player compensation (#465)

## Behavior

`Replacement Player Compensation` is host-controlled and enabled by default.

- When a human leaves an active pilgrimage, CT snapshots that player's granted
  power-ups, persistent buffs, Pilgrim's Coin, and serialized melee/ranged Deus
  weapons. The next replacement bot using that profile receives the snapshot.
  If the bot uses another career, its own compatible weapon models are retained
  and regenerated at the departing human's exact melee/ranged rarity tiers.
- When a human joins and vanilla selects a bot to remove, CT copies the selected
  bot's power-ups and persistent buffs to the incoming player's profile row.
  Same-career replacements retain the serialized weapons exactly. Cross-career
  replacements retain the joining career's compatible weapons and project the
  replaced bot's two rarity tiers onto them. The incoming player's Pilgrim's Coin
  is set to the host's current balance.
- Once the target loadout row exists, the copied profile and peer rows are marked
  initialized. Any later vanilla initial-setup or currency RPC is then a no-op
  instead of overwriting the handoff.
- If the bot is selected before that initial-setup RPC arrives, CT defers the copy,
  lets vanilla create the target-career weapon row, and completes the handoff once
  from `rpc_deus_set_initial_setup`. If the RPC arrived first, the `remove_bot`
  boundary completes it immediately. This removes the network-order race without
  polling.
- Spawn data is rebuilt once after a bot-to-human handoff, before the player is
  spawned, so their first visible loadout consumes the compensated state.
- Human-to-bot handoff also refreshes vanilla's local Deus backend/talent row and
  equips both bot slots through CT's existing canonical bot-weapon primitive. A
  SharedState-only copy is insufficient because vanilla built the bot backend
  loadout before `_add_bot` returns.
- Every five-field write is read back immediately. A mismatch or setter error
  restores the complete prior row and initialization flags; the snapshot is not
  consumed or appended a second time.

## Engine boundary

Vanilla stores progression in `DeusRunState` under peer/local-player/profile/career
keys. `GameModeDeus.player_left_game_session` is the last reliable point at which a
departing human's keyed state can be captured. `GameModeDeus._add_bot` and
`GameModeDeus.remove_bot` are the exact bot creation/removal boundaries. The latter
returns the actual bot selected for the joining human, so no heuristic player match
is required. `DeusRunController.rpc_deus_set_initial_setup` is the authoritative
host receiver that materializes a joining career's initial loadout when it loses
the race with bot selection.

The handoff writes existing vanilla SharedState fields. It sends no custom RPCs,
does not poll per frame, and caps diagnostics at 32 lines per run (`[ct:465]`).
Cloning is bounded to six table levels and 256 entries per snapshot. Exceeding
either bound rejects the handoff before any write rather than truncating progression.

The diagnostic lines name source and target profile/career, whether the application
was immediate or deferred, projection failures by slot, read-back/rollback result,
parity removals, and bot backend/status refresh result. A missing source row is also
logged rather than silently ignored.

## Wire safety

Before a snapshot is written, CT checks the existing peer-parity beacon. When parity
is not positively proven, CT-owned power-up and persistent-buff identifiers are
filtered from that copy. Vanilla progression still transfers. This prevents a late
joiner without CT from receiving an unknown network lookup index.

## Co-op verification

1. Host and client enable the candidate CT dev build and leave Replacement Player
   Compensation enabled. Begin a Chaos Wastes run.
2. Give the client at least two visible boons, spend or collect coins so their balance
   differs from the host, and upgrade or swap both weapon slots. Record both rarities.
3. Client disconnects. Confirm the same-profile replacement bot has the client's
   boons and both weapon tiers; the log must contain one `human->bot` line whose
   `apply=true`, `talents=true`, `weapons=true`, and `status=true` receipts all pass.
4. Continue playing, grant the bot another boon or weapon upgrade, then let the client
   reconnect. Confirm the returning player receives the bot's current boons and both
   weapons, while their coin balance exactly matches the host. Require one
   `bot->human` line and no `parity_filtered` entries when both peers run CT.
5. Repeat with the setting disabled. The vanilla fresh-state behavior must remain.
6. Repeat steps 2-4 after choosing a different career for that hero than the host's
   configured bot career. Both rarity tiers must transfer without giving either
   target a weapon from the wrong career; `[ct:465]` must report `projection=exact`
   or only explicit fail-closed slot details, never an incompatible serialized item.
7. Repeat one leave/rejoin cycle quickly enough to exercise whichever network order
   occurs. An `awaiting=rpc_deus_set_initial_setup` line must be followed by exactly
   one `deferred-finish`, or the immediate path must emit exactly one `bot->human`.
8. Run `/ct_regression_test` and require `replacement_player_compensation_installed`
   to pass.
