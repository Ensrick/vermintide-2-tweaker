# Crowbill Pick/Hammer Mode Contract

This began as the engine-free contract for the Imperial Crowbill (Kruber and
Saltzpyre), Dawi Crowbill (Bardin), and the optional vanilla Sienna Crowbill
capability. `_cwv_crowbill_runtime.lua` now owns live input, local gameplay
template selection, bounded state transport, and lifecycle replay; model and
preview composition remains centralized in `_cwv_crowbill_presentation.lua`.

## Source-backed donor

All variants use the exact `one_handed_crowbill` donor from
`scripts/settings/equipment/weapon_templates/1h_crowbills.lua` in the extracted
Vermintide 2 source. The policy changes only the `damage_profile` reference on
the eight direct release actions:

- Heavy: `heavy_attack`, `heavy_attack_left`, `heavy_attack_right_up`.
- Light: `light_attack_left`, `light_attack_right`, `light_attack_last`,
  `light_attack_upper`, `light_attack_bopp` (the push follow-up).

Charge starts, animation events, animation scales, attack windows, total times,
chain actions, block, push, wield, state machine, and sounds remain exact donor
data. This also covers the two direct actions which use shared profiles
(`light_blunt_smiter_stab_burn` and `light_pointy_smiter`), rather than assuming
that every Crowbill action has `crowbill_1h_*` in its profile name.

## Hammer-mode balance

`_cwv_crowbill_hammer_mode.lua` clones the complete donor template, each used
damage profile, and every referenced power row. It then applies:

- attack and impact cleave x 1.60;
- direct attack power x 0.85 (impact/stagger power is unchanged);
- light normal-armor and super-armor attack modifiers set to zero, matching
  vanilla one-handed hammer light-attack non-armor-piercing semantics.

Generated names are deterministic. Existing generated rows are reused, so
rebuilding cannot compound multipliers. Vanilla/shared rows and the donor
template are never mutated. Pick mode therefore remains the exact original and
does not require a destructive restore pass.

## Mode and presentation boundary

Weapon Special changes one stable weapon identity between `pick` and `hammer`.
The policy emits a compact transition only when that value changes, using
channel `cwv_crowbill_mode_v1`, schema 1, a validated identity capped at 96
characters, and a two-value mode enum. The runtime owner may also replay this
state at bounded lifecycle edges (join, equip, respawn, transition), but must
not publish from an update/per-frame path.

The gameplay template and visible model must be selected from the same cached
mode. Hammer presentation is an exact 180-degree rotation about the weapon's
local longitudinal/haft axis, local Z `(0, 0, 1)`; pick mode is zero degrees.
Apply the absolute mode rotation at weapon spawn/wield and compose it with any
committed per-weapon transform. Do not add 180 degrees repeatedly.

All peers register the pick and hammer templates/profiles unconditionally
before gameplay lookup freeze. The owning peer authoritatively publishes mode;
receivers validate the fixed schema and use it only to choose already-local
gameplay/presentation data. No damage tables, animation data, transforms, or
arbitrary item keys travel over the wire.

## Runtime integration

Both pre-registered templates carry the same `action_three` Weapon Special.
A real toggle stores mode on the exact backend instance, destroys and recreates
only the owner's equipped melee unit, and lets the existing
`BackendUtils.get_item_template` owner choose the pick or hammer template. The
remote wire item remains Sienna's vanilla Crowbill identity.

Presentation state uses an authenticated `family:peer:slot` identity. A receiver
accepts a state only from the peer who owns that player unit, for `slot_melee`,
with a known Crowbill family key and the fixed pick/hammer enum. Wield, husk
wield, game-state entry, peer-parity reconnection, and query/reply are bounded
replay edges. No update callback sends mode traffic.

When any peer lacks CWV, VMF does not deliver this mod channel. The existing
CWV damage-profile parity gate maps every generated hammer profile back to its
exact donor profile before a modded client sends a hit to an unconfirmed host.
The absent peer therefore sees the normal Crowbill face and receives vanilla
profile identifiers rather than an unknown NetworkLookup index.

Disabling CWV restores the active local Crowbill to pick mode before runtime
selection is turned off. The optional `Sienna Crowbill Hammer Mode` setting is
off by default; Imperial and Dawi Crowbills always retain the capability.

## In-game verification gate

The automated contract is complete. Before #604 is verified in game, confirm:

1. local 1P, local 3P, bot, remote husk, inventory, and score-preview rotation;
2. late-join/equip/respawn state replay without repeated messages;
3. mixed-CWV/no-CWV lobby degradation without disconnect or lookup errors;
4. two-player verification that pick/hammer damage, cleave, light armor bounce,
   animation timing, and visible head orientation agree on both peers.
