# Chaos Wastes Tweaker — Feature To-Do

> **REFERENCE ONLY — not current status.** Unchecked and completed entries may
> be stale. GitHub Issues is the sole current tracker; retain this file only for
> design evidence that is not yet captured in an issue.

Planned features for ct. See `PER_BOON_SCALING_BOONS_PLAN.md` and `FORTUNES_OF_WAR_PLAN.md` for detailed designs of in-flight families.

## Altar cost configuration

Allow changing the coin cost of:
- Random boon altars
- Weapon swap altars
- Weapon temper altars

Each as a configurable setting in the mod options.

**How to apply:** Altar costs likely live in `DeusPowerUpTemplates` or similar CW globals — research needed.

## Chaos Wastes inventory access

Open an inventory UI during CW expeditions that uses the **Chaos Wastes inventory system** (not the standard keep inventory), so players can **store and retrieve weapons they gain** during the expedition instead of simply swapping them away at altars.

This is distinct from the `general_tweaker` "inventory in missions" feature — it should hook into the CW weapon pool.

**Why:** Players currently lose weapons permanently when swapping at altars. A storage system lets them keep interesting drops and swap back later.

**How to apply:** Needs research into how CW weapon drops are tracked. New ct feature.

### TODO: Fix inventory access in adventure missions (cross-ref)

> — OBSOLETE 2026-07-07 (the in-mission inventory feature MOVED from general_tweaker to gui_tweaker (gut) and now works — invoked as `/gut_inv`, adventure-only. The gt `mission_inventory_enabled` toggle described below is superseded. Retained as plumbing reference for the CW-storage feature.)

The `general_tweaker` `mission_inventory_enabled` toggle was added (v0.2.1-dev) but doesn't actually work yet. Patching `InventorySettings.inventory_loadout_access_supported_game_modes` alone is insufficient — there's likely a `game_mode:menu_access_allowed_in_state()` check in `ingame_ui.lua` (line ~617) that also blocks it. Needs further investigation. Listed here because the CW-storage feature builds on the same plumbing.

## Per-boon scaling boons (new boon family)

The user's favorite existing boon grants **+1% damage and +1% attack speed per boon** (`boon_meta_01`). Sweet spot: not OP, not mediocre, and gives every junk boon some baseline value. Add a small family of siblings in the same mold:

- **+1% stagger power and +1% cleave per boon**
- **+1% crit chance and +5% crit power per boon**
- **+1% health and +1% increased healing/THP gain per boon**
- **+2% cooldown reduction per boon**

**Why:** These reward boon stacking generically, so even a "bad" boon roll has marginal value. Mirrors the design of the existing damage/attack-speed-per-boon boon the user already enjoys.

**How to apply:** Implement as new entries in the CW boon pool (`DeusPowerUpTemplates`). Stat hooks should multiply by current boon count at evaluation time (or update on boon pickup). Confirm naming/icons match the existing per-boon boon for discoverability. **Detailed plan: `PER_BOON_SCALING_BOONS_PLAN.md`.**

### Constraint reminders for any new boon
- Use only rarities `{event, rare, exotic, unique}` — `common`/`plentiful` crash. See `DEVELOPMENT.md` § "Deus boon rarities".
- If runtime injection: dual-register into `DeusPowerUpBuffTemplates` AND `_G.BuffTemplates`. See `DEVELOPMENT.md` § "Buff registration".
- For ammo / overcharge effects: prefer `reduced_overcharge` over `max_overcharge` (engine network bound caps the latter at ~60). See `DEVELOPMENT.md` § "Custom boon design".
