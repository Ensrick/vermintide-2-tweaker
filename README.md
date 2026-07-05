# Vermintide 2 Tweaker Monorepo

Welcome to the **Vermintide 2 Tweaker Monorepo**! This repository hosts a collection of modular mods for the cooperative action game **Warhammer: Vermintide 2**, built using the **Vermintide Mod Framework (VMF)** and running on the **Stingray engine**.

Originally starting as a monolithic mod called "Tweaker", the project has been modularized into separate, focused sub-mods to ensure stability, easier maintenance, and compatibility.

---

## 🗺️ Mod Directory

Below is an overview of the mods contained in this repository. 

Some mods feature a **dev/stable split** (marked with a `-dev` suffix) where active development is tested in a friends-only Workshop item before merging and publishing stable updates to the public Workshop item.

| Mod / Directory | Short ID | Workshop ID | Stream | Description |
| :--- | :---: | :---: | :---: | :--- |
| [weapon_tweaker](file:///c:/GitHub5/vermintide-2-tweaker/weapon_tweaker) | `wt` | [3712896117](https://steamcommunity.com/sharedfiles/filedetails/?id=3712896117) | Single | **Cross-character weapon access:** Allows careers to equip weapons native to other characters with 3P animation mapping. |
| [cosmetics_tweaker](file:///c:/GitHub5/vermintide-2-tweaker/cosmetics_tweaker) | `cosmetics` | [3715714222](https://steamcommunity.com/sharedfiles/filedetails/?id=3715714222) | Single | **Cosmetics Overrides:** Unlocks skins/hats, allows offhand/shield visual swaps, and features a glow-mesh RGB picker. |
| [character_weapon_variants](file:///c:/GitHub5/vermintide-2-tweaker/character_weapon_variants) | `cwv` | [3716869446](https://steamcommunity.com/sharedfiles/filedetails/?id=3716869446) | Single | **New Weapon Variants:** Registers brand-new items combining models, animations, and stats (uses `MoreItemsLibrary`). |
| [chaos_wastes_tweaker](file:///c:/GitHub5/vermintide-2-tweaker/chaos_wastes_tweaker) | `ct` | [3712929235](https://steamcommunity.com/sharedfiles/filedetails/?id=3712929235) | Stable | **Chaos Wastes Tuning:** economy, blessings, curses, boons, altars, and traits adjustments. |
| [chaos_wastes_tweaker_dev](file:///c:/GitHub5/vermintide-2-tweaker/chaos_wastes_tweaker_dev) | `ct_dev` | [3733366926](https://steamcommunity.com/sharedfiles/filedetails/?id=3733366926) | Dev | In-flight testing clone for `ct`. |
| [general_tweaker](file:///c:/GitHub5/vermintide-2-tweaker/general_tweaker) | `gt` | [3713619122](https://steamcommunity.com/sharedfiles/filedetails/?id=3713619122) | Stable | **Utilities:** 3rd person camera, noclip, godmode, and host-side lobby controls (reservations, idle kicking, etc.). |
| [general_tweaker_dev](file:///c:/GitHub5/vermintide-2-tweaker/general_tweaker_dev) | `gt_dev` | [3733367409](https://steamcommunity.com/sharedfiles/filedetails/?id=3733367409) | Dev | In-flight testing clone for `gt`. |
| [gui_tweaker](file:///c:/GitHub5/vermintide-2-tweaker/gui_tweaker) | `gut` | [3732144878](https://steamcommunity.com/sharedfiles/filedetails/?id=3732144878) | Single | **UI Enhancements:** Repositionable HUD components (buffs, abilities) and loadout swapping controls. |
| [dynamic_cosmetic_portraits](file:///c:/GitHub5/vermintide-2-tweaker/dynamic_cosmetic_portraits) | `dcp` | [3721036701](https://steamcommunity.com/sharedfiles/filedetails/?id=3721036701) | Single | **Dynamic HUD Portraits:** UI portraits that dynamically adapt to the wearer's current equipped hat/skin. |
| [crafting_in_modded](file:///c:/GitHub5/vermintide-2-tweaker/crafting_in_modded) | `cim` | [3721038774](https://steamcommunity.com/sharedfiles/filedetails/?id=3721038774) | Stable | **Forge UI:** Custom Athanor crafting menu for modded-realm weapon generation. |
| [crafting_in_modded_dev](file:///c:/GitHub5/vermintide-2-tweaker/crafting_in_modded_dev) | `cim_dev` | [3733366851](https://steamcommunity.com/sharedfiles/filedetails/?id=3733366851) | Dev | In-flight testing clone for `cim`. |
| [event_tweaker](file:///c:/GitHub5/vermintide-2-tweaker/event_tweaker) | `event` | [3721290755](https://steamcommunity.com/sharedfiles/filedetails/?id=3721290755) | Single | **Mutator / Event Picker:** Host-side dropdown controls to force game event modes and custom mutators. |
| [modded_progression](file:///c:/GitHub5/vermintide-2-tweaker/modded_progression) | `mp` | [3730422873](https://steamcommunity.com/sharedfiles/filedetails/?id=3730422873) | Single | **Local Progression:** Simulates XP, Okri's challenges, loot chest reward flows locally in modded realm. |
| [verminious_dreams_lighting](file:///c:/GitHub5/vermintide-2-tweaker/verminious_dreams_lighting) | `vdl` | [3727221800](https://steamcommunity.com/sharedfiles/filedetails/?id=3727221800) | Stable | **Lighting Overhaul:** Lighting environment overrides custom tuned for the Verminious Dreams campaign. |
| [verminious_dreams_lighting_dev](file:///c:/GitHub5/vermintide-2-tweaker/verminious_dreams_lighting_dev) | `vdl_dev` | [3733366748](https://steamcommunity.com/sharedfiles/filedetails/?id=3733366748) | Dev | In-flight testing clone for `vdl`. |

---

## 🗺️ Repository Architecture & Documentation

Before starting development or troubleshooting, please refer to the extensive documentation available in this repository:

- **[`PROJECT_STANDARDS.md`](file:///c:/GitHub5/vermintide-2-tweaker/PROJECT_STANDARDS.md)**: The operational rulebook. Guides coding styles, file constraints (keep files under 2500 lines), logging conventions, and pre-ship checklists.
- **[`CLAUDE.md`](file:///c:/GitHub5/vermintide-2-tweaker/CLAUDE.md)**: Technical reference explaining hook consolidation, build pipelines, directory purposes, and bug-triaging procedures.
- **[`MOD_OWNERSHIP.md`](file:///c:/GitHub5/vermintide-2-tweaker/MOD_OWNERSHIP.md)**: Coordination registry mapping active developers/agents to mods, preventing code collisions.
- **[`CROSS_MOD_ARCHITECTURE.md`](file:///c:/GitHub5/vermintide-2-tweaker/CROSS_MOD_ARCHITECTURE.md)**: Outlines how the different mods interface at runtime (e.g. `cosmetics_tweaker` identifying `weapon_tweaker` or `character_weapon_variants` to apply visual overrides).

---

## 🧪 Development Workflow

1. **Check for In-Flight Work**: Read [MOD_OWNERSHIP.md](file:///c:/GitHub5/vermintide-2-tweaker/MOD_OWNERSHIP.md) and check `.in_progress/` directory to ensure no other developer or agent is editing the same mod.
2. **Consolidate Hooks**: *Strict VMF rule:* Consolidate hooks on the same target function into single methods using files like `_safe_hook.lua` to prevent the engine from discarding duplicate hook setups.
3. **Build & Deploy**: Utilize `vmb-launcher` script tools and execute deployment using helper scripts:
   ```powershell
   # Deploy a specific mod
   .\upload_wt.ps1
   # Run the QA verification checks
   .\qa\run_all.ps1
   ```
4. **Log Cleanly**: Adhere to prefix formatting for console output, prefixing logs with `[<mod_id>:<feature>]`.

---

## 📄 License
This project is licensed under the MIT License - see the [LICENSE](file:///c:/GitHub5/vermintide-2-tweaker/LICENSE) file for details.
