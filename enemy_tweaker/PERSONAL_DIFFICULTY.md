# Personal Difficulty (#61)

Enemy Tweaker 0.7.46-dev implements the safe first slice of personal difficulty:
a per-human combat handicap enforced by the host. It does not claim to run two
different game difficulties in one session; VT2's spawns, AI, enemy health,
wounds, and pacing are shared host-authoritative simulation state.

## Behavior

Each human chooses **Personal difficulty** under **Enemy Spawns**. `Auto` is the
default and changes nothing. A selection at or below the real host difficulty
also changes nothing. A higher selection applies this bounded approximation:

| Rank gap | Enemy damage to that player | That player's damage to enemies |
|---:|---:|---:|
| 1 | 1.08x | 0.95x |
| 2 or more | 1.25x | 0.85x |

Only hostile-AI combat damage is in this slice. Friendly fire, self/environmental
damage, bots, pet damage, healing, stamina, attack speed, scoreboard adjustment,
and spawn/health/AI changes remain vanilla. Those surfaces need independent
design and should not be hidden behind a misleading “full difficulty” label.

## Authority and wire contract

The client sends `(ET_RPC_SCHEMA, requested_preset)` to the real host peer id.
The host ignores messages on clients or with the wrong schema and keys accepted
state only by VMF's authenticated `sender_peer_id`; a payload cannot name another
player. Three delayed sends cover VMF handshake timing, and the request is sent
again only when the host/local-peer/preset context changes—there is no per-frame
or per-hit RPC.

The host applies the factor once on entry to
`DamageUtils.apply_buffs_to_damage`, before vanilla buffs/procs and network quantization. No buff template,
`NetworkLookup` entry, shared breed mutation, or client-side damage prediction is
introduced. Peers must run the same Enemy Tweaker version for client requests to
arrive; a missing/mismatched peer safely remains at host difficulty.

## Unit lifetime boundary

Area damage stores `source_attacker_unit` when its extension is initialized and
forwards that reference on later buffered ticks [src:
`scripts/unit_extensions/weapons/area_damage/area_damage_extension.lua:32,373`].
The source enemy can already be deleted by then. Personal difficulty therefore
checks `Unit.alive` before every owner or breed lookup. A nil/deleted source cannot
establish hostile identity, so the hook preserves vanilla damage. Auto/off and
at-or-below-host factors skip attacker classification completely. Crash session
`404228a8-e78a-4431-b59b-58a74079edfe` and issue #640 establish this boundary.

## Verification

Lifecycle: `verify-fix` plus the orthogonal `coop-required` qualifier.

1. Host a Champion mission with one client; both run Enemy Tweaker 0.7.46-dev.
2. Leave the host on Auto. Set the client to Cataclysm.
3. Against the same ordinary enemy attack, confirm only the client receives the
   1.25x result. Confirm the client's direct damage to an ordinary enemy is 0.85x.
4. Set the client to Champion or Auto and confirm both paths return to vanilla.
5. Confirm friendly fire, a barrel/fall, a bot, and a necromancer pet stay vanilla.
6. Kill a Poison Wind Globadier while standing in its lingering poison and
   confirm later poison ticks do not crash after the Globadier despawns.
7. Run `/et_regression_test`; `issue61_personal_handicap_authoritative` and
   `issue640_personal_handicap_unit_lifetime` must pass.
