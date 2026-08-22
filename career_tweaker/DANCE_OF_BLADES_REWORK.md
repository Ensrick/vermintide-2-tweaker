# Dance of Blades rework (#473)

## Source mapping

Dance of Blades is the talent internally named
`kerillian_maidenguard_versatile_dodge`. Vanilla's single `on_dodge` driver
branches on `status_extension.blocking`: while blocking it temporarily applies
the native improved dodge-distance and dodge-speed buffs; otherwise it grants a
two-second power buff.

The opt-in rework retains the blocking branch and replaces the non-blocking
dodge reward with a hit-driven risk/reward stack:

- each enemy hit grants 2% damage dealt;
- each enemy hit also increases damage taken by 2% (equivalent to losing 2% damage
  reduction);
- up to 15 stacks, for 30% damage dealt and 30% increased damage taken;
- every stack has its own two-second lifetime; later hits do not refresh older
  stacks;
- blocking dodges retain the authored 20% dodge-distance benefit and matching
  vanilla dodge-speed handling.

`damage_dealt` is used rather than `power_level`, so the benefit does not also
inflate stagger. VT2 enforces `max_stacks` through a bucket keyed by each
sub-buff's `name`, not by the top-level template. The outgoing and incoming
halves therefore use distinct local names so neither consumes the other's
15-entry cap. `damage_taken` uses its dedicated name as `stacking_name`; VT2
sums that bucket before applying it, producing the requested linear 30% at 15
stacks rather than compounding 1.02 fifteen times.

## Network and lifecycle

The three top-level dodge, proc, and stack names are registered unconditionally
and alphabetically for stable `NetworkLookup` indices. The outgoing and
incoming sub-buff names are local identities and never enter `NetworkLookup`.

The vanilla talent is buffered on both client and server. Its reworked hit proc
is therefore explicitly `authority = "server"`: an owning client does not grant
a stack locally, while the host grants exactly one after the native
`rpc_buff_on_attack` reaches it. Host-local and bot hits also grant exactly once.
That one writer routes through Career Tweaker's existing live peer-parity
wrapper. The rework is marked network-unsafe, so it degrades to the complete
vanilla talent whenever any human peer has not confirmed Career Tweaker. No new
RPC is added.

Turning the setting off restores the talent's exact original buff list and
returns the three custom templates to their permanent no-op stubs. Existing
stacks naturally expire within two seconds; a new mission or talent reapply is
the canonical way to test a toggle change.

## Verification

1. Enable **Handmaiden: Dance of Blades hit-stack rework**, equip Dance of
   Blades, then start a fresh mission.
2. Dodge without blocking and without hitting an enemy: no damage stack should appear.
3. Hit enemies more slowly than two seconds apart: each stack should disappear
   two seconds after its own hit rather than all stacks refreshing together.
4. Hit rapidly and confirm the visible stack count caps at 15.
5. Compare outgoing damage at zero and 15 stacks; it should rise by 30%.
6. Take a controlled hit at zero and 15 stacks; damage taken should rise by 30%.
7. Dodge while blocking and confirm the native 20% distance benefit remains.
8. Run `/crt_regression_test`; require
   `issue473_dance_of_blades_contract` to pass.
9. Only after the solo walk passes, repeat with a second Career Tweaker peer in
   both host/client ownership directions and confirm a client-owned Handmaiden
   still gains exactly one pair per hostile hit.
