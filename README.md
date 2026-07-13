# Vermintide 2 Tweaker

[![QA](https://github.com/Ensrick/vermintide-2-tweaker/actions/workflows/qa.yml/badge.svg)](https://github.com/Ensrick/vermintide-2-tweaker/actions/workflows/qa.yml)

Vermintide 2 Tweaker is a Windows-focused monorepo of modular
[Vermintide Mod Framework](https://vmf-docs.verminti.de/) mods for
*Warhammer: Vermintide 2*. The project began as one `tweaker` mod and now keeps
each gameplay, UI, cosmetic, and tooling concern in a focused mod.

These mods target the modded realm. Subscribe through the linked Steam
Workshop pages and follow each page's dependency and compatibility notes.
Development builds are testing surfaces and may change frequently.

## Mod directory

This table is the canonical inventory of tracked mod directories. Versions live
in each mod's `CHANGELOG.md`; they are intentionally not duplicated here.

| Directory | VMF ID | Stream | Workshop | Purpose |
|---|---|---|---|---|
| [`career_tweaker`](./career_tweaker/) | `crt` | Single | [3716286199](https://steamcommunity.com/sharedfiles/filedetails/?id=3716286199) | Swap and tune career talents and abilities. |
| [`chaos_wastes_tweaker`](./chaos_wastes_tweaker/) | `ct` | Stable | [3712929235](https://steamcommunity.com/sharedfiles/filedetails/?id=3712929235) | Tune Chaos Wastes economy, curses, boons, altars, and traits. |
| [`chaos_wastes_tweaker_dev`](./chaos_wastes_tweaker_dev/) | `ct_dev` | Dev | [3733366926](https://steamcommunity.com/sharedfiles/filedetails/?id=3733366926) | Friends-only development stream for `ct`. |
| [`character_weapon_variants`](./character_weapon_variants/) | `character_weapon_variants` | Single | [3716869446](https://steamcommunity.com/sharedfiles/filedetails/?id=3716869446) | Add new weapon variants built from cross-character templates and assets. |
| [`cosmetics_tweaker`](./cosmetics_tweaker/) | `cosmetics_tweaker` | Single | [3715714222](https://steamcommunity.com/sharedfiles/filedetails/?id=3715714222) | Unlock and customize hats, skins, weapon models, shields, and illusions. |
| [`crafting_in_modded`](./crafting_in_modded/) | `cim` | Stable | [3721038774](https://steamcommunity.com/sharedfiles/filedetails/?id=3721038774) | Provide modded-realm crafting and Athanor forge surfaces. |
| [`crafting_in_modded_dev`](./crafting_in_modded_dev/) | `cim_dev` | Dev | [3733366851](https://steamcommunity.com/sharedfiles/filedetails/?id=3733366851) | Friends-only development stream for `cim`. |
| [`dynamic_cosmetic_portraits`](./dynamic_cosmetic_portraits/) | `dynamic_cosmetic_portraits` | Single | [3721036701](https://steamcommunity.com/sharedfiles/filedetails/?id=3721036701) | Match HUD and hero-select portraits to equipped cosmetics. |
| [`enemy_tweaker`](./enemy_tweaker/) | `enemy_tweaker` | Single | [3716780252](https://steamcommunity.com/sharedfiles/filedetails/?id=3716780252) | Customize enemy spawns, breed substitutions, and horde composition. |
| [`event_tweaker`](./event_tweaker/) | `event_tweaker` | Single | [3721290755](https://steamcommunity.com/sharedfiles/filedetails/?id=3721290755) | Select and combine live-event presets and mutators. |
| [`general_tweaker`](./general_tweaker/) | `gt` | Stable | [3713619122](https://steamcommunity.com/sharedfiles/filedetails/?id=3713619122) | Add camera, debug, host, lobby, and gameplay utilities. |
| [`general_tweaker_dev`](./general_tweaker_dev/) | `gt_dev` | Dev | [3733367409](https://steamcommunity.com/sharedfiles/filedetails/?id=3733367409) | Friends-only development stream for `gt`. |
| [`gui_tweaker`](./gui_tweaker/) | `gut` | Stable | [3732144878](https://steamcommunity.com/sharedfiles/filedetails/?id=3732144878) | Save loadouts and customize HUD layout. |
| [`gui_tweaker_dev`](./gui_tweaker_dev/) | `gut_dev` | Dev | [3751024698](https://steamcommunity.com/sharedfiles/filedetails/?id=3751024698) | Friends-only development stream for `gut`. |
| [`modded_progression`](./modded_progression/) | `mp` | Single/private | 3730422873 | Recreate vanilla progression locally in the modded realm without PlayFab writes. |
| [`verminious_dreams_lighting`](./verminious_dreams_lighting/) | `verminious_dreams_lighting` | Stable | [3727221800](https://steamcommunity.com/sharedfiles/filedetails/?id=3727221800) | Override lighting for the Verminious Dreams missions. |
| [`verminious_dreams_lighting_dev`](./verminious_dreams_lighting_dev/) | `verminious_dreams_lighting_dev` | Dev | [3733366748](https://steamcommunity.com/sharedfiles/filedetails/?id=3733366748) | Friends-only development stream for the lighting mod. |
| [`weapon_tweaker`](./weapon_tweaker/) | `wt` | Single | [3712896117](https://steamcommunity.com/sharedfiles/filedetails/?id=3712896117) | Enable cross-character weapon access with third-person animation remapping. |
| [`weapon_tweaker_dev`](./weapon_tweaker_dev/) | `wt_dev` | **Stale; do not edit** | — | Abandoned experiment clone; all weapon work belongs in `weapon_tweaker`. |
| [`weapons_of_chaos`](./weapons_of_chaos/) | `WOC` | Single | [3753880932](https://steamcommunity.com/sharedfiles/filedetails/?id=3753880932) | Adapt enemy weapons and keep artifacts into player-usable items. |
| [`tweaker`](./tweaker/) | `t` | **Frozen legacy** | [3704660429](https://steamcommunity.com/sharedfiles/filedetails/?id=3704660429) | Original monolith retained for history; do not extend it. |

The five stable/dev pairs are `ct`, `cim`, `gt`, `gut`, and
`verminious_dreams_lighting`. New work goes into their `_dev` directory and is
promoted deliberately. All other active mods are single-stream.

## Contributing

Start with [CONTRIBUTING.md](./CONTRIBUTING.md). A first local validation takes
three commands after cloning:

```powershell
Set-Location vermintide-2-tweaker
./tools/install-hooks.ps1
./qa/run_all.ps1 -Quick -SkipLua
```

The quick gate validates repository policy without launching the game. Building,
deploying, and uploading require the separate
[VMBLauncher](https://github.com/Ensrick/vmb-launcher) setup; contributors do
not need it for documentation, issue triage, or most static QA work.

## Documentation

- [CONTRIBUTING.md](./CONTRIBUTING.md) — human-first setup and change workflow.
- [PROJECT_STANDARDS.md](./PROJECT_STANDARDS.md) — binding engineering and issue
  lifecycle rules.
- [docs/BUG_TRIAGE_RUNBOOK.md](./docs/BUG_TRIAGE_RUNBOOK.md) — evidence-first bug
  investigation.
- [docs/engine/README.md](./docs/engine/README.md) — source-cited engine subsystem
  references and per-mod engine surfaces.
- [docs/CROSS_MOD_ARCHITECTURE.md](./docs/CROSS_MOD_ARCHITECTURE.md) — runtime
  relationships between mods.
- [qa/CHECKS.md](./qa/CHECKS.md) — QA tiers, policies, and bug-class coverage.
- [CLAUDE.md](./CLAUDE.md) — extended maintainer and coding-assistant technical
  reference. It is not required for the five-minute contributor setup.

Open work lives in [GitHub Issues](https://github.com/Ensrick/vermintide-2-tweaker/issues),
not in new roadmap documents. Please use the issue forms so runtime authority,
source seams, and verification topology are captured before implementation.

## License

Licensed under the [MIT License](./LICENSE).
