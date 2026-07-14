# Bot boon economy (#466)

## Implemented foundation

The existing mutually exclusive bot modes still decide whether bots mirror the
host's boon or roll an independent eligible boon of the same rarity. Version
0.7.278-dev makes those choices participate in a real independent economy:

- Every host-owned bot has its own `DeusRunState` soft-currency row.
- A fresh bot is seeded from the host's live balance. The #465 replacement-player
  handoff may then replace that seed with the departing human's balance.
- Positive coin pickups credited to the host are credited by the same final,
  multiplier-adjusted amount to each current bot.
- A purchased boon altar charges the exact altar cost, including CT's reuse cost
  multiplier. A bot that cannot afford it receives no boon.
- Direct shrine-shop purchases now reach bots; vanilla's `_try_buy_power_up` does
  not call `add_power_ups`, which is why the older mirror implementation missed
  this source. Each bot pays the rarity and discount-adjusted shop price.
- Chest of Trials and end-of-level rewards remain free, matching the source.
- Weapon swaps and upgrades calculate cost from each bot's current weapon rarity.
  Insufficient funds leave the bot's weapon unchanged. A failed grant/equip refunds
  its charge.

All writes use vanilla SharedState fields. There is no new RPC and no per-frame
polling. `[ct:466]` transaction/choice diagnostics are capped at 64 lines per run.
CT-owned boon names retain the #426 peer-parity gate.

## Weighted choices

Career/talent/weapon-weighted boon selection remains a later policy layer. The
issue does not yet contain the requested curated priority list, so inventing one
would encode balance decisions not supplied by the project owner. The current
random mode remains rarity-matched, disabled-boon-aware, and peer-parity-safe.
The independent ledger and common shrine/altar/CoT source coverage implemented
here are the stable substrate that a curated scorer can use later without changing
economy or grant plumbing.

## Co-op verification

1. Host and client run CT v0.7.278-dev. Enable one bot boon mode and Shared
   Reliquaries. Start with at least one bot.
2. Collect coins and confirm `[ct:466] credit` rows show the same final earned amount
   for each bot, with independent before/after balances.
3. Spend enough through one bot-affordable boon altar. Confirm each affordable bot
   gets one boon and is charged the altar's displayed cost.
4. Drain one bot below the next altar cost, then buy again. That bot must receive no
   boon; another affordable bot must still receive and pay for its choice.
5. Buy a shrine boon. Repeat both affordable and insufficient cases. In Random mode,
   bot choices must be eligible boons of the purchased rarity; Mirror mode uses the
   host's exact boon.
6. Complete a Chest of Trials. Bots receive the configured mirror/random reward with
   `cost=0` and no balance reduction.
7. Use weapon swap and upgrade altars with one affordable and one insufficient bot.
   Only the affordable bot changes weapon, and its charge must match its own current
   rarity-to-target cost.
8. Run `/ct_regression_test`; require `bot_boon_economy_installed` to pass. Attach the
   host log containing `[ct:466]` if any decision differs.

