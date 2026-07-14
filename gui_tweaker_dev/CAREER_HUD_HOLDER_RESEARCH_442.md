# Career-themed HUD holders (#442)

## Source boundary

The requested holder is not part of the draggable health frame. It is the
`EquipmentUI` `background_panel` texture behind the local health bar and inventory
slots. Every update, vanilla reads the active career name and selects
`UISettings.hud_inventory_panel_data[career_name]`, falling back to `.default`
(`scripts/ui/hud_ui/equipment_ui.lua:350-359`). Therefore one data entry per
career is sufficient; another `EquipmentUI` hook would duplicate ownership.

Vanilla currently supplies three panel definitions:

- default: `hud_inventory_panel`, 624 x 66;
- Outcast Engineer: `hud_inventory_panel_cog`, 630 x 73
  (`scripts/settings/ui_settings.lua:813-830`);
- Warrior Priest: `hud_inventory_panel_priest`, 624 x 111, merged through DLC
  settings (`scripts/settings/dlcs/bless/bless_ui_settings.lua:25-34`).

The other eighteen hero careers use the generic fallback. `[gut:442]` records this
catalog in two bounded lines and the runtime regression alerts if the vanilla seam
or dedicated set changes after a game update.

## Potential-fix contract

Completion requires eighteen new authored holder textures, each with intentional
transparent padding and a stated native size. They must be compiled into a GUT UI
atlas/package before Lua references them; source code cannot manufacture native
Stingray atlas resources at runtime. Each texture should preserve the health bar,
ammo, consumable, ability, and input-icon clear zones at 16:9 and ultrawide HUD
scales. Engineer and Priest art remain the two vanilla controls.

Once approved assets exist, implementation is data-only at the engine boundary:

1. load the holder atlas/package with the HUD lifetime;
2. merge one `{ texture_id, texture_size }` entry for each remaining career into
   `UISettings.hud_inventory_panel_data`;
3. provide one default-on master and per-career opt-outs, restoring the exact
   prior entry rather than forcing the generic texture;
4. test keyboard/mouse and gamepad layouts, spectator transitions, career swaps,
   every HUD scale, 16:9, 21:9, and 32:9;
5. unload only GUT's package reference at HUD teardown.

No network synchronization is needed: this is owner-local presentation. The HUD
drag editor continues moving `EquipmentUI.pivot`; the holder naturally follows
because it is already a child of that component.
