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
unrelated `versus_base`. The policy searches for Cata 5, then 4, then 3, and
caps at the highest registered tier. It never advances into Versus. This honors
the requested Cata 5 ceiling when a compatible tier provider is installed while
remaining safe on stock VT2.

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
