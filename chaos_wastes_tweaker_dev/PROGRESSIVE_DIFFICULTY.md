# Progressive Difficulty (#460)

The master option is off by default. When enabled, its two advanced settings
are independent:

- Difficulty increases occur only at map 3 and map 5 when their sub-toggle is on.
- Coin progress reduction applies from map 3 onward to the configured Coin
  Pickup Multiplier. It is a percentage of that multiplier, not a flat coin subtraction.

`DeusRunController.get_run_difficulty` remains the difficulty seam. The starting
difficulty is captured from `setup_run`, while `get_completed_level_count()`
provides the stable mission ordinal: completed counts 2 and 4 are maps 3 and 5.
The path graph is generated once and is not reshaped by this read-time override.

Vanilla defines `cataclysm`, `cataclysm_2`, and `cataclysm_3`, followed by the
unrelated `versus_base`. The policy advances only through contiguous registered
tiers and caps before the first gap. It never advances into Versus. This honors
the requested Cata 5 ceiling when a compatible provider registers both Cata 4
and Cata 5, while a partial provider cannot cause a jump over a missing tier.

The original difficulty and the two diagnostic throttles live on each
`DeusRunController`, not on the mod singleton. At ordinary run start,
`setup_run` supplies the original run difficulty. Vanilla hot join is different:
`DeusMechanism.sync_mechanism_data` serializes `get_run_difficulty()`, which is
already stepped. The host therefore sends the immutable original tier in one
schema-gated `ct_progdiff_start` message immediately before vanilla's setup RPC;
the joining client consumes it once when constructing its controller. Replacing
a controller or starting a later run cannot inherit another run's ramp state.

Source seams audited in the 2026-07-19 decompile:

- `deus_mechanism.lua:930-964` (`sync_mechanism_data` and its setup RPC)
- `deus_mechanism.lua:1179-1198` (controller construction and `setup_run`)
- `deus_run_controller.lua:273-284` (the stored run difficulty and graph build)

Coin pickup continues through the existing `on_soft_currency_picked_up` hook.
From map 3, effective multiplier is:

`coin_multiplier * (1 + progressive_coin_reduction / 100)`

The final award retains the existing minimum of one coin. Both settings use the
host-effective settings mirror, so verification requires a host and client.

Verification:

1. Start on Legend with Progressive Difficulty enabled and difficulty increase on.
2. Confirm maps 1-2 are Legend, maps 3-4 are Cataclysm, and map 5 is Cataclysm 2.
3. Set Coin Pickup Multiplier to 2.00 and reduction to -25.
4. Confirm pickups use 2.00x on maps 1-2 and 1.50x from map 3 for both peers.
5. Disable only the difficulty sub-toggle: difficulty must remain fixed while coin reduction remains active.
6. Disable the master: both behaviors must return to vanilla/configured baseline.
7. Run `/ct_regression_test`; `progressive_difficulty_installed` must pass.
