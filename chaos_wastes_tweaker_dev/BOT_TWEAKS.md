# Bot tweaks category (#331)

Version 0.7.280-dev gives bot-facing options one top-level **Bots** category.
It contains Blessed Bots, boon announcements, mirrored/random boon choices,
mirrored weapon altar purchases, and the new automatic Pilgrim's Coin pickup.
Existing setting ids and saved values are unchanged; this is a presentation move,
not a settings migration.

## Automatic Pilgrim's Coin pickup

The implementation follows the game's Money Magnet boon instead of inventing a
second pickup transaction. Once per second, each living host-owned bot asks the
vanilla `PickupSystem` for pickups within the same 10-metre radius. For an exact
`deus_soft_currency` result, its existing `InteractorExtension` starts the stock
forced `pickup_object` interaction. The normal pickup extension, game mode, coin
roll, audio, event, run-state, coin multiplier, and #466 bot-ledger paths remain
the only authorities. The source pattern is at
`morris_buff_settings.lua:1209-1257`; its one-second interval is authored at
`deus_power_up_settings.lua:3547-3554`, and the 10-metre value at
`tweak_data/buff_tweak_data.lua:406-408`.

The feature does not teleport, destroy, duplicate, or directly credit a pickup.
It ignores every non-coin pickup. A 1.5-second local claim prevents multiple bots
from racing the same unit while the vanilla interaction completes. Claims are
bounded by the number of live pickup units and are cleared when the feature is
disabled. Diagnostics emit at most 32 `[ct:331]` rows per process.

The work is consolidated into CT's existing `PlayerBotBase.update` hook alongside
Blessed Bots. The coin path has a one-second throttle; Blessed Bots retains its
independent two-second throttle. No new hook, RPC, network lookup, or per-frame
pickup query is added.

## Verification

1. Enable **Bots Automatically Pick Up Pilgrim's Coins** and start a Chaos Wastes
   mission with at least one bot.
2. Leave a coin within 10 metres of a bot. The bot should collect it through the
   normal interaction, and the coin/audio/HUD behavior should match a player pickup.
3. Place health, ammunition, potions, bombs, and event pickups nearby; this option
   must not interact with them.
4. Put two bots near one coin and confirm the pickup is credited once.
5. Start an interaction or combat pressure on a bot and confirm the feature does
   not replace an interaction already in progress.
6. Disable the option and confirm bots stop initiating coin pickups.
7. Run `/ct_regression_test` and require `issue331_bot_coin_pickup_installed` to pass.
