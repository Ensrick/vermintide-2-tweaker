# Hidden career passives (#153)

## Implemented slice

Tweaker: GUI now surfaces two source-confirmed Witch Hunter Captain bonuses in
the talent screen's passive description: **Power of Sigmar** (+25% headshot
damage) and **Sigmar's Charm** (+5% base critical-strike chance). The feature is
read-only and enabled by default under **Talents**.

The PC and console talent windows already read `PassiveAbilitySettings.perks`,
but WHC's source data omits these two entries. The +25% value comes from
`victor_witchhunter_headshot_multiplier_increase` in
`talent_settings_victor.lua`; the critical bonus is the difference between
WHC's `base_critical_strike_chance = 0.1` and the standard career baseline of
`0.05` in `career_settings.lua`.

## Safety and Career Tweaker composition

The implementation runs after vanilla `_populate_career_info` on both talent
window classes and appends text only to the already-created passive description
widget. It does not add buffs, edit attributes, append to
`PassiveAbilitySettings.perks`, select talents, or send network traffic.
Career Tweaker may append its own real perk records (for example innate
Abandon); those remain vanilla-rendered and are neither copied nor overwritten.

Automatic conversion of arbitrary buff names into player-facing claims is not
safe. `/gut_hidden_passive_probe` therefore emits a bounded one-line census for
each career so further source-confirmed entries can be catalogued deliberately.

## Solo verification

Enable **Surface Hidden Career Passives**, open Witch Hunter Captain's Talents
screen, and confirm both named bonuses appear below the passive description.
Switch careers and confirm ordinary passive descriptions remain unchanged.
Toggle the setting off, reopen the screen, and confirm the added lines disappear.
Run `/gut_regression_test` and confirm
`issue153_hidden_passives_display_only` passes.
