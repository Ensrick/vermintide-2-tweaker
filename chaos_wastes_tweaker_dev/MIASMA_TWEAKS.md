# Rotten Miasma customization (#361)

Version 0.7.281-dev adds a **Rotten Miasma** subgroup under Curses with three
host-effective settings:

- **Permanent Purifying Torch Carrier** (off by default): after a living player
  picks up the relic, the safe area remembers that unit when the relic is
  dropped. A later carrier takes ownership.
- **Safe Area Radius**: 2-30 metres, defaulting to vanilla's 8 metres.
- **Miasma Stack Interval**: 0.1-5 seconds, defaulting to vanilla's 1.3 seconds.

The implementation preserves the game's single networked
`rotten_miasma_safe_area_01` unit. Vanilla creates it, applies
`curse_rotten_miasma`, updates the relic target, and deletes it when the mutator
stops (`mutator_curse_rotten_miasma.lua:82-149`). CT wraps the live
`MutatorTemplates.curse_rotten_miasma.server.update` dispatch, calls vanilla
exactly once, then repositions that same unit to the remembered living carrier.
It does not create an aura, RPC, buff identifier, or network lookup.

The existing buff owns both the effective distance calculation and the visual
flow radius (`morris_buff_settings.lua:499-568`). CT updates its live `radius`
and the unit's `radius` flow data together. Exposure timing remains the native
`buff_exposure_tick_rate`; its vanilla value and radius array are authored at
`morris_buff_settings.lua:6137-6153`.

## Co-op verification

1. Host enables Permanent Carrier, sets radius to 12, and interval to 0.5.
2. Enter a Rotten Miasma mission with a client. Both peers should see the same
   12-metre sphere and gain/lose stacks at the faster interval.
3. Host picks up and then drops the purifying relic. The sphere must continue
   following the host while the relic remains on the ground.
4. Client picks up the relic. The sphere must transfer to and follow the client.
5. Disable Permanent Carrier. Dropping the relic must restore vanilla behavior.
6. Run `/ct_regression_test`; `issue361_miasma_customization_installed` must pass.
