# Hidden career passives (#153)

## Implemented slice

Tweaker: GUI now surfaces two source-confirmed Witch Hunter Captain bonuses in
the talent screen's native **Perks** presentation: **Power of Sigmar** (+25%
headshot damage) and **Sigmar's Charm** (+5% base critical-strike chance). The
six-row console layout renders them as two independent entries. The compact
three-slot PC layout uses one combined tooltip row so neither bonus is dropped.
The feature is read-only and enabled by default under **Talents**.

The PC and console talent windows already read `PassiveAbilitySettings.perks`,
but WHC's source data omits these two entries. The +25% value comes from
`victor_witchhunter_headshot_multiplier_increase` in
`talent_settings_victor.lua`; the critical bonus is the difference between
WHC's `base_critical_strike_chance = 0.1` and the standard career baseline of
`0.05` in `career_settings.lua`.

## Safety and Career Tweaker composition

The implementation wraps vanilla `_populate_career_info` on both talent-window
classes. It gives that synchronous call a shallow presentation copy of the
existing `PassiveAbilitySettings.perks`, then restores the exact original table
even when vanilla throws. It does not add buffs, edit attributes, persistently
append to `PassiveAbilitySettings.perks`, select talents, or send network traffic.
Career Tweaker may append its own real perk records (for example innate
Abandon); the shallow presentation list preserves those exact records by
reference and never overwrites them.

Automatic conversion of arbitrary buff names into player-facing claims is not
safe. `/gut_hidden_passive_probe` therefore emits a bounded one-line census for
each career so further source-confirmed entries can be catalogued deliberately.

## Solo verification

Enable **Surface Hidden Career Passives**, open Witch Hunter Captain's Talents
screen, and confirm both named bonuses appear under **Perks**, not under Witch Hunt.
Switch careers and confirm ordinary passive descriptions remain unchanged.
Toggle the setting off, reopen the screen, and confirm the added lines disappear.
Run `/gut_regression_test` and confirm
`issue153_hidden_passives_display_only` passes.
