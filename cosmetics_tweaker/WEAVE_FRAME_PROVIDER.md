# Weave Season 5-10 frame provider

Issue: [#1000](https://github.com/Ensrick/vermintide-2-tweaker/issues/1000)

## Source status

The decompiled game atlases declare all 24 Season 5-10 inventory sprites
(`scripts/ui/atlas_settings/gui_items_atlas.lua:20920-21255`,
`icon_portrait_frame_season_05_quickplay` through `..._10_tier_3`) and all 24
HUD sprites (`scripts/ui/atlas_settings/gui_hud_atlas.lua:6318-8208`,
`portrait_frame_season_05_...` through `..._10_...`). Each season has
`quickplay`, `tier_1`, `tier_2` and `tier_3`.

Vanilla registers no usable identity for them:

- `scripts/settings/equipment/item_master_list_exported.lua:3190-3249` defines the
  Season 4 frame items (`frame_season_04_quickplay` .. `_tier_4`) and nothing for
  Seasons 5-10.
- `scripts/settings/equipment/cosmetics.lua:3085-3099` ends the Weave frame
  cosmetics at Season 4.
- `scripts/settings/ui_player_portrait_frame_settings.lua:2688` onward ends the
  rendered frame templates at Season 4.
- The spawn initializer and `rpc_set_equipped_frame` send the frame through
  `NetworkLookup.cosmetics` (`scripts/network/game_object_initializers_extractors.lua:50,89`;
  `scripts/entity_system/systems/cosmetic/cosmetic_system.lua:53-81`), so the 24
  absent identities have no vanilla wire ids.

Season 4 rows name their text `portrait_frame_season_04_<tier>_name` /
`_description`. Whether the shipped localization also carries Season 5-10 text
under that convention cannot be read from the decompile [unverified].

## Slice 1: provider and census (implemented)

`_cos_weave_frame_catalog.lua` is the deterministic, data-only provider for the
six guide rows, ordered Ghyran, Azyr, Ulgu, Shyish, Ghur, Chamon, each with
Quickplay and the guide's 40/80/120 thresholds. The wind labels and thresholds
come from the guide linked on the issue; vanilla source only numbers the seasons.

`_cos_unlocks.lua` (the portrait-frame owner) publishes it as
`mod._cos.weave_frames`, API version 1:

| Call | Result |
|---|---|
| `count()` | 24 |
| `entries()` / `get(key)` / `seasons()` / `tiers()` | snapshot copies, so one consumer cannot mutate what another sees |
| `census(item_master, cosmetics, frame_settings, cosmetic_lookup)` | per-table count of unregistered keys (rawget only) |
| `atlas_census(has_atlas_entry)` | inventory and HUD sprite presence through a predicate such as `UIAtlasHelper.has_atlas_settings_by_texture_name` |
| `localization_census(localize)` | how many vanilla-convention names/descriptions resolve to real text |

The provider registers nothing: no `ItemMasterList`, `Cosmetics`,
`UIPlayerPortraitFrameSettings`, fake inventory or `NetworkLookup` write.
Modded Progression can consume the same provider when seasonal earning is built.

`/cos_1000_diag` prints one bounded line:

```text
[cos:1000:diag] census frames=24 inventory_atlas=<n> hud_atlas=<n> vanilla_names=<n> vanilla_descriptions=<n> unregistered_items=<n> unregistered_cosmetics=<n> unregistered_templates=<n> unregistered_lookup=<n>
```

It answers the two unknowns the registration slice depends on:

1. Live atlas residency. Fewer than 24 `inventory_atlas` or `hud_atlas` means
   the missing sprites must be packaged (extracted-atlas provenance retained)
   before registration.
2. Vanilla naming. `vanilla_names=24` means registration reuses vanilla text;
   otherwise names need authoring or an explicit decision on the issue.

The four `unregistered_*` counts must stay 24 until registration ships; a lower
count means a game update or another mod already registered an identity, and
registration must skip that key rather than overwrite it.

## Remaining phases (not implemented)

2. Register item, cosmetic and portrait-template rows locally; inject fake
   ownership only in the modded realm through the existing single
   `PlayFabMirrorAdventure._create_fake_inventory_items` owner. Never append to
   `NetworkLookup.cosmetics`; treat any existing identity as a collision.
3. Persist the semantic frame key per career; intercept a Season 5-10 selection
   before `HeroViewStateOverview._set_loadout_item` reaches the strict numeric
   lookup or the official loadout; keep the vanilla frame as the official and
   native-wire fallback.
4. Versioned Cosmetics semantic replay for matching mod peers (spawn, hot join,
   career swap, mission transition, host migration, clear/replacement).
5. Per-player presentation on owner, remote human, bot, HUD, Tab/player list,
   score/team, lobby, character-select and inventory surfaces; never mutate a
   shared career/profile frame globally.
6. Modded Progression earning/rotation as a provider consumer.

A July archive (`b006f7f4`, 1,744 Lua tests at the time) covered phases 2-3 for
owner surfaces only. The August deep review on the issue asks for replay to be
complete before registration is integrated.

## Constraints already proven elsewhere

- #402: modded-only selection must never persist into official loadouts.
- #435: renderer overrides are keyed per player; a shared career/profile write
  leaks one player's appearance to another.
- #526: HUD, Tab and score-screen portraits depend on the vanilla silhouette and
  alpha contract.
- #713: the fake inventory mirror rebuilds repeatedly, so injection must be
  idempotent and quiet.
- #925: cached presentation views need one owned refresh adapter.
