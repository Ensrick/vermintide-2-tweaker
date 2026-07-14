# Boon price rework (#467)

## Current source contract

Vanilla does not assign a price to each boon. Shrine prices are keyed only by
rarity in `DeusCostSettings.shop.power_ups`: event 100, rare 200, exotic 250,
and unique 300 Pilgrim's Coins. Boon altars are a separate flat-price purchase
(`DeusCostSettings.deus_chest.power_up`, stock 150). Chest of Trials rewards are
free.

The live roll hierarchy has four valid serialized rarities: `event`, `rare`,
`exotic`, and `unique`. Moving a boon between them changes more than its shop
price: it changes roll buckets, reward color/presentation, and the rarity carried
in synchronized run state. `common` and `uncommon` are not valid active boon-pool
tiers even though unrelated cost or item tables contain those names.

Individual prices would require one canonical deterministic manifest plus every
consumer to use it: shrine widget text, affordability/button state, telemetry,
local purchase, and host RPC validation. Changing only the buyer or only the UI
would create misleading prices or host/client coin divergence.

## Armed census

Version 0.7.279-dev adds an observation-only census. The first Chaos Wastes run
setup in a process automatically writes one tab-safe record for every live boon:

`[ct:467] row name=<id> rarity=<tier> shop=<coins> display=<name> description=<text>`

It also writes tier counts and anomalies for a missing price, missing template,
or the same boon appearing in multiple rarity buckets. Records are sorted and
capped at 192; descriptions are whitespace-normalized and capped at 240
characters. The audit runs on host and client, adds no RPC, and mutates no pool,
template, price, or run-state data. `/ct_boon_price_audit` is available only as a
manual re-run convenience; normal evidence collection requires no command.

## Decision needed before balance mutation

The issue does not yet provide the new hierarchy or individual values. The census
is intended to supply the complete current baseline so the project owner can
return a manifest such as:

```lua
boon_id = { rarity = "exotic", price = 225 }
```

The rarity may be omitted when only an individual shrine price changes, and the
price may be omitted when only the tier changes. Until that curated manifest is
approved, the mod deliberately leaves gameplay unchanged rather than inventing
balance values.

## Verification

1. Start one Chaos Wastes run; no command is required.
2. Confirm the log contains one `[ct:467] summary`, tier summaries, then sorted
   rows with current rarity, price, resolved name, and description.
3. Confirm the final line reports the emitted/truncated/anomaly counts. Stock plus
   the current CT additions should fit below the 192-row cap.
4. Run `/ct_regression_test` and require `boon_price_audit_armed` to pass.
5. Compare host and client summaries. Their tier counts and anomaly set must match.

Once the curated manifest exists, implementation must update the full UI,
purchase, telemetry, RPC-validation, bot-economy, and roll-pool boundaries together
and receive co-op verification.
