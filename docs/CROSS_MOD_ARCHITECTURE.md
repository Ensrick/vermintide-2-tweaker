<!--
REVIEW (2026-05-01): Content is conceptually accurate post-VMB migration (this file is mostly
about runtime cross-mod detection patterns, which don't change with the build pipeline).
Two minor points:
1. Mod 3 ("character_weapon_variants") line below says it has Workshop ID — should be cross-checked.
   itemV2.cfg has published_id = 3716869446L; deploy_all.ps1 maps "character_weapon_variants" to
   "3716869446". CLAUDE.md and DEVELOPMENT.md still say "(unpublished)" — those are wrong.
2. The detection pattern uses get_mod("wt") and get_mod("character_weapon_variants") — both correct.
3. The LA Bridge section is detailed and accurate as far as the LA-clone backend pattern goes
   (matches feedback_cwv_backend_id_lookup.md).
-->
# Cross-Mod Architecture — Weapon Sharing & Cosmetics

## Overview

Three mods with distinct responsibilities, designed to work independently but enhance each other when co-installed.

| Mod | Role | Dependencies |
|-----|------|-------------|
| **weapon_tweaker** | Unlocks existing weapons across careers (same item, different wielder) | None |
| **cosmetics_tweaker** | Cosmetic customization: offhand illusions, skins, icons, glow maps | None (optional: character_weapon_variants, MoreItemsLibrary, modded_progression) |
| **character_weapon_variants** | Adds brand-new weapon items combining models from multiple characters | MoreItemsLibrary (optional: modded_progression) |
| **modded_progression** | Re-enables 100% of vanilla progression in modded realm (XP, loot, currency, Okri's challenges, Lohner's, crafting bench). All state local. | None |

---

## weapon_tweaker ↔ character_weapon_variants: independent; wt is the availability control surface

> **Spec (2026-07-05, Issue #368) — supersedes the earlier "wt suppresses/defers to CWV" model
> described in the interface-point bullets below.** The two mods operate **independently**;
> neither suppresses the other, and overlap is expected and allowed (the same weapon may be
> reachable on the same receiver through both).

- **wt** provides cross-character *access* — it expands vanilla `ItemMasterList[key].can_wield`
  so an existing weapon is wieldable by a new career. **CWV** provides *variant items* (new cloned
  IML entries, marked `entry.cwv_variant = true`) **plus** its own cross-access `can_wield`
  expansions on vanilla keys. Both may cover the same weapon+receiver; that is fine.
- **CWV is default-on with no per-weapon toggles.** It makes its weapons available at load and
  exposes no enable/disable UI (only a few feature checkboxes).
- **wt is the availability control surface.** It owns the per-weapon enable/disable toggles
  (`unlock_<career>_<weapon_key>`). When **both** mods are installed:
  - Overlapping cross-character weapons **default ON** in wt (matching CWV's default-on, so
    installing wt never silently disables what CWV already grants). wt's standalone defaults
    (cross-char ports OFF) apply only when CWV is **absent**.
  - **wt's menu also covers CWV's weapons.** For CWV's genuinely-new cloned variant items
    (`cwv_variant == true`), wt exposes a backward-compatible per-item master plus independent
    authored-career availability toggles (all default-on); for overlapping vanilla-key access,
    wt's existing static toggles apply (#391).
  - **wt's toggle is authoritative** — disabling a weapon in wt removes the receiver from
    availability regardless of which mod added it (wt is the last writer of `can_wield`, running
    on every game-state transition, i.e. after CWV's load-time expansion).
- **Removed:** the `_cwv_managed` cede table + `cwv_skip` gate in `apply_weapon_unlocks` (wt no
  longer withholds `wh_1h_falchion` / `wh_dual_wield_axe_falchion` on Kruber when CWV is present).

Implementation is tracked in **Issue #368** (deferred pending go-ahead; includes fixing a live
`wh_1h_axe`-on-Kruber clobber where wt's strip-rebuild removed CWV's unlock every state transition).

---

## Mod 1: weapon_tweaker

**Responsibility:** Allow any character to equip any other character's existing weapons.

- Patches `can_wield` on `ItemMasterList` entries so career restrictions are lifted
- Handles animation remapping so cross-career weapons play correctly on the new skeleton
- Does NOT create new items — it unlocks existing ones
- Does NOT handle cosmetics — the weapon keeps whatever skin/illusion it already has

**What it does NOT do:**
- No new ItemMasterList entries
- No model swaps or cosmetic overrides
- No shield mixing across characters
- No custom icons or descriptions

**Interface point with character_weapon_variants:** independent, overlap allowed — wt is the
availability control surface. See the "weapon_tweaker ↔ character_weapon_variants" section above
(Issue #368). wt does **not** suppress unlocks for weapons CWV provides; instead its per-weapon
toggles default ON when CWV is installed and cover CWV's own variant items per career (#391).

---

## Mod 2: cosmetics_tweaker

**Responsibility:** Cosmetic customization — offhand illusion swaps, weapon skins, hat/outfit unlocks, glow maps, custom icons.

### Core features (independent, no other mods needed)
- **Offhand illusion swap:** Per-character curated shield/offhand options on the weapon customization screen
  - Options table keyed by `character + weapon_type`
  - Selection state keyed by `character + weapon_type` (no cross-character bleed)
  - Only shows lore-appropriate options for the current character by default
- **Hat/skin unlocks:** Intra-character cosmetic sharing
- **Weapon glow maps:** RGB color picker for `rune_emissive_color`
- **Custom illusion injection:** New weapon skins via WeaponSkins table patching

### CWV integration (implemented in cosmetics_tweaker)
- Detects the real mod id with `get_mod("character_weapon_variants")`.
- Discovers the seven authored CWV dual-weapon families and builds independent
  left/right cosmetic pools for them; package preloading and saved-offhand
  restore wait until that catalogue is available.
- This behavior lives in `cosmetics_tweaker`. CWV's own
  `_detect_companion_mods()` helper does not enable it; that helper only records
  optional-mod presence for CWV's status/log output.

### weapon_tweaker integration
- `cosmetics_tweaker` resolves `get_mod("wt")` only at the features that need
  it (for example, avoiding a duplicate Moonfire impact puff while wt's AOE
  revert is active).
- Do not infer a general cosmetic-default handshake from mod presence. Any new
  wt/cosmetics integration must identify and document its concrete consumer.

### What it does NOT do
- Does not create new weapon items (that's the character_weapon_variants)
- Does not unlock weapons across careers (that's weapon_tweaker)
- Does not change weapon mechanics, stats, or movesets

---

## Mod 3: character_weapon_variants

**Responsibility:** Create brand-new weapon items that combine models, animations, and stats from different characters into lore-friendly packages.

### Examples
| New Weapon | Character | Source Models | Notes |
|-----------|-----------|-------------|-------|
| Imperial Axe and Shield | Kruber | Saltzpyre's axe + Kruber's empire shields | Axe fits imperial aesthetic |
| Imperial Spear and Shield | Kruber | Kerillian's spear moveset + Kruber's shields | Different stats/moveset from Kruber's own spear+shield |
| (more TBD per case-by-case curation) | | | |

### Architecture
- **MoreItemsLibrary** (hard dependency) to register new `ItemMasterList` entries
- Each new weapon is a real networked item with:
  - Unique `item_key` (e.g., `kruber_imperial_axe_shield`)
  - Custom `inventory_icon` and `hud_icon`
  - Custom `description` text differentiating it from similar weapons
  - Proper `can_wield` restricted to intended character(s)
  - `left_hand_unit` / `right_hand_unit` pointing to the desired model combination
- Weapons obtained through a **crafting menu** (in-mod or via cosmetics_tweaker's planned crafting UI)
- **Multiplayer safe:** Items are real backend objects, network-replicated — all players with the mod see the same thing

### What it does NOT do
- No career unlocking (weapon_tweaker handles that)
- No cosmetic variation within a weapon (cosmetics_tweaker handles offhand swap etc.)
- No animation remapping (inherits from whatever weapon template it's based on, or weapon_tweaker provides remaps)

### Interface points
- **weapon_tweaker:** independent — wt does NOT defer to CWV's items (that "defer" model is retired, Issue #368). Both mods may cover the same weapon+receiver; wt is the availability control surface and, when installed alongside CWV, exposes a compatible item master plus authored-career toggles for every catalogued `cwv_variant` item (CWV itself has no availability controls). See the "weapon_tweaker ↔ character_weapon_variants" section at the top of this doc.
- **Combat Style animation handoff:** CWV alone owns active style and donor-template
  selection. Its optional
  `get_effective_combat_style_template_name(item, backend_id, owner_unit, slot_name)`
  contract supplies WT with a template name for owner or synchronized remote-husk
  wield state. WT validates the name against `Weapons`, then selects its existing
  per-template 3P remap. Missing, disabled, failed, unsupported, or unregistered
  providers fall back to the item's native template; WT never duplicates style
  family mappings.
- **cosmetics_tweaker:** cosmetics detects CWV directly and discovers authored
  dual-family offhand pools. CWV's companion-detection return values remain
  diagnostic-only.

---

## Optional-mod detection

There is no shared three-mod handshake. Each consumer resolves the sibling it
actually needs, at the feature boundary that consumes it:

```lua
-- In cosmetics_tweaker:
local cwv = get_mod("character_weapon_variants")  -- nil if not installed
local weapon_tweaker = get_mod("wt")               -- nil if not installed

if cwv then
    -- cosmetics_tweaker discovers CWV dual-family offhand pools
end

if weapon_tweaker then
    -- gate one concrete wt-aware behavior
end
```

CWV also resolves `wt` and `cosmetics_tweaker` in
`_detect_companion_mods()`, but those return values are consumed only by
`/cwv` status output. They are not feature flags. No hard dependencies are
created by these optional lookups; each mod's core features work standalone.

### CIM ↔ CWV backend-ID convention (load-bearing)

CIM and CWV do not exchange ownership through `get_mod()`. A crafted CWV
instance uses the wire/render identity `cwv_<item-key>_<three digits>`; CWV's
resolvers consume that shape to recover the variant definition when vanilla has
collapsed the item back to its inherited base key. CIM's active dev stream owns
crafted instances by exact membership in `_forged_weapons` (#592), not by this
prefix. Its legacy saved-loadout migration still recognizes `cwv_`-prefixed IDs
so an older CWV loadout is not purged before migration can resolve it.

The `cwv_` prefix is therefore a compatibility contract, not a general
"modded-item ownership" test. If its shape changes, update together:

- CWV `_cwv_key_for_item` and other backend-ID resolvers;
- CIM's CWV minting/selector compatibility paths;
- CIM's legacy `_modded_loadout_purge_stale` exception; and
- this section plus both mods' regression coverage.

### CIM ↔ WOC optional trait capability

WOC owns `woc_poisoned_edge`, its `WeaponTraits` row, and its native Hagbane
proc. CIM owns only discovery and saved-instance persistence. WOC offers the
exact capability `woc.poison_trait.v1`; CIM validates the owner/capability/row
before adding the trait to its melee pool. If WOC is absent, CIM parks the key
outside the live item's `traits` array and restores it only after the provider
returns. WOC's unconditional loadout shadow removes the active custom key before
vanilla `NetworkLookup.traits` encoding, so this optional integration creates no
hard dependency and no custom lookup id reaches an unmodded or non-WOC peer.

### CIM ↔ Cosmetics optional exact-glow persistence

Cosmetics owns glow identity, validation, preview, rendering, and peer replay.
CIM owns only the durable synthetic-item record and exposes three public seams:
`_cim_get_craft`, `_cim_set_custom_glow`, and
`_cim_register_restore_callback`. Apply may mirror one opaque, bounded,
versioned `{provider, schema, identity, state}` blob into the exact craft.

Cosmetics-local `glow_per_item` state has precedence. CIM is consulted only on
a local miss and a blob is accepted only when its backend-item plus illusion
identity exactly matches the requested Cosmetics identity. Restore clears only
that matching blob. `cim_dev` takes precedence when both streams are present;
an absent, older, incomplete, or throwing sibling fails closed to Cosmetics'
standalone store. CIM never interprets the payload or invokes a material API,
and Cosmetics never assumes that every backend item belongs to CIM. With
Cosmetics absent the blob remains inert and the resident vanilla material wins.

---

## Loremaster's Armoury Bridge (cosmetics_tweaker ↔ LA)

> LA doc ownership map (issue #432): THIS section owns the bridge end-to-end
> architecture (clone registration, apply gate, loadout cache, preview hooks).
> `cosmetics_tweaker/LA_SYNC_MODEL.md` owns LA's OWN internals (no-sync evidence,
> shared-material paint, husk pipeline) + the §6 gotcha catalogue.
> `docs/LA_SYNC_CORE_AUDIT.md` owns the sync-state invariants + migration status.
> `MOD_DEPENDENCIES.md` owns the dependency/gating rows. Don't restate across them.

Exposes Loremaster's Armoury (LA) cosmetic recolors as separate equippable items in VT2's native inventory, so the player can have "Pureheart Red" and "Pureheart White" selectable side-by-side without LA's normal mode (which silently overrides a vanilla item's textures based on a VMF settings dropdown).

**Dependencies:** Loremaster's Armoury, MoreItemsLibrary (MIL). Both optional — bridge is a no-op if either is missing.

**Files:**
- `cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_la_bridge.lua` — clone registration, apply gate, texture routing
- `cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua` — loadout hooks, preview hooks, diagnostic commands (search for "LA bridge" / "la_bridge" / "loadout" sections)

### How it works end-to-end

#### 1. Clone Registration (boot time, `_la_bridge.lua:register_all`)

Iterates `LA.SKIN_LIST`, filters for `swap_hand == "hat" or "armor"`, matches each variant's `new_units[1]` to a vanilla `ItemMasterList` key via a unit-path index, then clones the IML entry:

```
backend_id = vanilla_key .. "_LA_" .. la_key
   e.g. "questing_knight_hat_0001_LA_Kruber_Pureheart_helm_red"
```

Clone entry modifications (`build_clone_entry`):
- `entry.key = suffix_id` — unique IML key
- `entry.name = suffix_id` — **critical**: the game's `parse_item_master_list()` sets `.name = key` on all IML entries at boot. Clones created after boot inherit the vanilla `.name` via `table.clone()`. If `.name` isn't overridden, `HeroWindowCharacterPreview._populate_loadout` thinks vanilla and clone are the same item and skips preview updates.
- `entry.display_name = suffix_id .. "_name"` — localization key, resolved via `_G.Localize` hook to "Human Readable (LA)"
- `entry.rarity = "exotic"` — orange border in the grid
- `entry.cos_la_armoury_key = la_key` — LA's internal key for texture lookup
- `entry.cos_la_vanilla_key = vanilla_key` — original hat key

Clones are registered with MIL via `mil():add_mod_items_to_local_backend(entries, "cosmetics_tweaker")` and added to `NetworkLookup.item_names` to prevent network-lookup crashes.

**Lookup tables** (all on the `M` module table):
| Table | Key → Value | Purpose |
|-------|-------------|---------|
| `backend_to_armoury` | clone backend_id → LA armoury_key | Identify which LA variant a clone represents |
| `backend_to_vanilla` | clone backend_id → vanilla IML key | Find the original hat for server-redirect and LA's `skin` arg |
| `armoury_to_backend` | LA armoury_key → clone backend_id | Gate: block LA from self-applying managed keys |
| `unit_path_to_clones` | vanilla unit path → list of clone backend_ids | In-game hook: detect when a clone's unit spawns |

#### 2. Apply Gate (`_la_bridge.lua:install_apply_gate`)

Raw function replacement on `LA.apply_new_skin_from_texture`. When a managed armoury_key fires AND `M._bridge_active` is false, the call is blocked. This prevents LA's own hooks (which watch loadout changes and queue texture swaps) from overriding vanilla hats with LA textures.

When the bridge itself wants to apply a texture, it sets `M._bridge_active = true`, calls the original function, then sets it back to false.

#### 3. Loadout Cache (cosmetics_tweaker.lua, `_install_skin_loadout_safety`)

Clone backend_ids must NEVER reach the PlayFab server — vanilla clients would crash on unknown ids. Pattern borrowed from AllHats mod (lines 38-71).

**Write hook** (`BackendUtils.set_loadout_item`):
- Clone equip → cache locally, do NOT call original (server never sees the clone id)
- Vanilla equip → clear cache entry, call original (server gets the vanilla id)

**CRITICAL**: Hook must be on `BackendUtils.set_loadout_item` (table-form), NOT on `items_iface.set_loadout_item`. The game's `_set_loadout_item` calls `BackendUtils.set_loadout_item()`, which dispatches via `Managers.backend:get_loadout_interface_by_slot(slot_name)` — this returns a DIFFERENT interface than `Managers.backend:get_interface("items")`. Hooking the items interface misses cosmetic slot writes entirely.

**Read hooks** (`items_iface.get_loadout`, `items_iface.get_loadout_item_id`):
- Merge cache into loadout reads so the game sees the clone as equipped
- Redirect any server-stored clone backend_ids to vanilla (defense against pre-hook leak)

**Startup fixup** (`_fixup_server_clones`):
- Reads raw server loadout (temporarily disabling cache), finds leaked clone ids, replaces them with vanilla via `get_loadout_interface_by_slot().set_loadout_item()` directly

#### 4. Preview Hooks (cosmetics_tweaker.lua)

**`MenuWorldPreviewer.equip_item` wrapping hook:**
When the cosmetics grid selects a clone, the game calls `equip_item(item_name, slot, backend_id)` where `item_name` is the vanilla key (from `item.data.name` which the game resolves from the backend item). The hook detects clone backend_ids and swaps `item_name` to the clone's `suffix_id`, so `ItemMasterList[suffix_id]` is used for spawn data (custom display name, custom rarity).

**`HeroPreviewer._spawn_item` / `MenuWorldPreviewer._spawn_item` wrapping hook:**
Sets `self._cos_la_spawning = backend_id` during clone spawns so downstream hooks (e.g. `_spawn_item_unit`) know to apply LA textures.

**Preview update mechanism** (`HeroWindowCharacterPreview._populate_loadout`):
The game compares `item.data.name` against the previewer's stored `item_name_by_slot_type()` to decide whether to re-equip. Since our clones have `entry.name = suffix_id` (unique per clone), switching between vanilla and any clone always triggers the re-equip.

#### 5. In-Game Texture Application

**`AttachmentUtils.link` hook** and **`HeroPreviewer._spawn_item_unit` hook_safe:**
When a hat unit spawns whose unit path matches a clone in `unit_path_to_clones`, the bridge checks whether that clone is equipped (via `find_active_clone_for_unit_path`). If so, it calls `apply_direct()` which:
1. Sets `M._bridge_active = true` (gate pass)
2. Calls `LA.apply_new_skin_from_texture(armoury_key, world, vanilla_key, unit)` directly
3. Sets `M._bridge_active = false`
4. Suppresses LA's queues for that unit to prevent double-application

If the vanilla hat is equipped (no clone), the bridge suppresses any LA queue entry for that unit.

### Diagnostic Commands

| Command | Purpose |
|---------|---------|
| `/la_dump` | Registry contents: all clone backend_ids and their armoury_keys |
| `/la_hats` | All hats for current career with VANILLA/CLONE labels, rarity, equipped status, cache state, raw server value |
| `/la_trace 1/0` | Per-hook tracing of every equip_item, _spawn_item, AttachmentUtils.link firing |
| `/la_force <key>` | Bypass detection, apply an LA variant directly to the player's spawned hat unit |
| `/la_loadout` | Dump loadout_cache contents |
| `/la_attach` | Walk player unit's attachment tree, dump unit_name/skin/hand per node |

### Lessons Learned (for future AI agents)

1. **`parse_item_master_list()` sets `.name = key`** on all IML entries at boot. Any entries added after boot (by MIL or direct IML insert) must set `.name` manually, or the preview system will treat them as identical to their clone source.

2. **`BackendUtils.set_loadout_item` ≠ `items_iface:set_loadout_item`**. The game dispatches loadout writes via `get_loadout_interface_by_slot()` which returns slot-specific interfaces. Hooking the items interface only catches weapon/trinket slots; cosmetic slots go through a different interface. Always hook `BackendUtils` directly for universal interception.

3. **Clone backend_ids MUST NOT reach the server.** Cache locally, merge into reads. If they leak (from sessions before hooks were installed), detect and replace on startup.

4. **LA's own hooks watch loadout changes and queue texture swaps autonomously.** The apply gate must block ALL managed armoury_keys by default, only opening for bridge-initiated calls via the `_bridge_active` flag.

5. **MIL does not propagate `rarity` for cosmetic items.** Setting `entry.rarity = "exotic"` and `mod_data.CustomData.rarity = "exotic"` on the clone entry does not guarantee the grid shows an orange border. The rarity may still read as "default" from the backend. Visual distinction relies primarily on the "(LA)" display name suffix.

6. **The preview character model is a separate `MenuWorldPreviewer` world**, not the in-game keep character. Hat changes in-game go through `attachment_extension:create_attachment_in_slot` on the player unit. Preview hat changes go through `MenuWorldPreviewer.equip_item` → `_spawn_item` → `_spawn_item_unit`.

7. **`_populate_loadout` only calls `equip_item` for items where `item.data.name ~= current_item_name`.** For melee/ranged, the condition is bypassed (`item_slot_type == "melee"` always passes). For hats/cosmetics, the `.name` check is the sole gate. This is why setting `.name = suffix_id` is critical.

---

## Cross-mod weapon presentation contract

`docs/WEAPON_APPEARANCE_STANDARD.md` owns the descriptor and adapter contract.
This section owns only cross-mod responsibility and precedence. It is normative;
an independent hook that produces a different icon, name, model, or fallback for
one UI surface is a contract violation, not a second source of truth.

### Provider and consumer ownership

- **character_weapon_variants** provides the authored variant's base item
  identity: item key, per-hand units, base display metadata, and base icons.
- **cosmetics_tweaker** provides a player's persisted cosmetic overrides when
  it can prove the target identity: primary/offhand illusion, composed
  primary-plus-offhand label, icon ownership, glow, and related resources.
- **crafting_in_modded / Athanor, inventory/customization UI, Hold-Tab, lobby,
  and score/team UI are consumers/adapters.** They render the resolved
  descriptor; they do not replace it by independently looking up the active
  slot's primary skin or vanilla item metadata.
- **weapon_tweaker** changes availability and animation behavior. Its presence
  alone is not authority to replace a cosmetic or authored-variant presentation.

For each descriptor field, precedence is:

1. a validated exact-instance cosmetic override from the field's owning
   provider;
2. the authored CWV or vanilla item/skin value represented by the available
   item identity; then
3. a resident, wire-safe vanilla fallback.

This is field precedence, not whole-descriptor replacement. For example, a
shield override may own the icon and offhand name while the authored primary
weapon still owns its primary name and right-hand unit. Once a provider has
resolved a field, a later consumer hook must not clobber it with a second lookup.

### Exact instance versus loadout snapshot

Inventory/crafting/customization paths may carry `backend_id` or
`ItemInstanceId`; those consumers may read per-instance persistence. Hold-Tab
does not. Vanilla stores its remote entry from `rpc_sync_loadout_slot` and renders
the reconstructed `player_loadouts()` item, which contains no backend instance
ID. `[src: scripts/managers/player/player_manager.lua:69-78]`
`[src: scripts/ui/views/ingame_player_list_ui_v2.lua:1450,1504-1536]`

A snapshot adapter may use only synchronized item evidence plus an explicitly
bounded `(wearer peer, slot)` presentation cache. It must not resolve the local
player's current backend item or guess an instance from the slot. If no matching
snapshot presentation exists, it leaves vanilla's reconstructed name/icon in
place.

### Capability, wire, and resource fallback

Before emitting a custom presentation field, the adapter must prove all three:

1. **mod/capability parity** — the observer has the provider/capability needed
   to understand the field;
2. **wire identity** — the synchronized identity is sufficient for that field;
3. **renderer resource closure** — the target renderer has the required
   unit/texture/icon/material/package registered and resident.

Renderer closure is consumer-local, not a synonym for package residency. A
spawned unit must have real material handles; a UI material must exist in the
exact Gui that draws it. Tweaker-owned optional calls fail closed on missing or
unknown proof. Global wrappers preserve unknown vanilla/third-party/Pusfume
inputs and may remove only a resource whose absence is positively proved. The
shared contract is `tools/shared_lib/_lib_resource_residency.lua` V2 and the
full-tree ratchet is `qa/native_resource_contracts.psd1` (#749).

Failure of any proof selects the vanilla fallback or omits an optional overlay.
Never send or inject a custom item key, localization key, unit, skin, icon,
material, or package path into a peer/renderer that has not proved it can resolve
that resource. A consumer may degrade presentation; it may not turn an optional
cosmetic into a missing-resource crash.

### Local presentation invalidation (#925)

Presentation providers and adapters coordinate successful local writes through
the bounded generation ledger in
`tools/shared_lib/_lib_ui_presentation_refresh.lua`. Cosmetics is the canonical
publisher when installed because it already owns the singleton
`BackendUtils.set_loadout_item` hook. GUT Dev publishes only when the generation
did not advance during its synchronous write, so it supplies the event when
Cosmetics is absent without double-publishing when Cosmetics is present. DCP is
currently a consumer for Mercenary hat/outfit invalidations.

The event is a hint to re-read the owning provider; it is not authoritative
presentation state. Payloads are whitelist-only strings, the ring and drain are
hard-bounded, consumers keep independent cursors, handler failures are isolated,
and schema conflict fails open. Nothing is sent over the network. A sibling mod
that is absent, older, or cannot attach simply keeps its existing behavior. This
also preserves the Pusfume boundary: an unknown career or provider is ignored,
never replaced or disabled.

When adding an adapter, reuse the ledger but keep the engine-specific render
operation at that surface. Publish only after success, consume exact identity,
coalesce a batch into one refresh, and add a bounded diagnostic plus an offline
fixture. Do not add polling, a second `BackendUtils.set_loadout_item` hook in the
same mod, or another persistent loadout cache.

---

## Multiplayer Compatibility Matrix

| Scenario | Visual Result |
|----------|--------------|
| All players have character_weapon_variants | Everyone sees correct models — real items sync via network |
| Host has character_weapon_variants, client doesn't | Current real-item wire remains mod-required unless a parity-safe fallback is proved. Do not claim compatibility or transmit a custom identity to an absent provider; the required safe result is the vanilla fallback described above. |
| Player A has cosmetics_tweaker, Player B doesn't | Offhand swaps are client-local only (player A sees their choice, player B sees vanilla) |
| Player A has cosmetics_tweaker + LA bridge, Player B doesn't | LA clone textures are client-local. Clone backend_ids never reach the server (loadout cache), so Player B sees the vanilla hat |
| Player A has weapon_tweaker, Player B doesn't | Cross-career weapons visible to both (items exist in backend), but animations may look wrong to player B |

### External compatibility target: Pusfume

Pusfume owns its career registration, synchronized career identity, profile and
loadout adapters, units, assets, packages, and configuration. Tweaker-family
mods consume none of those surfaces unless the Pusfume project manager defines
an explicit reviewed contract. In particular, a generic career hook must accept
an appended career it does not recognize and preserve the original call chain.

Optional Tweaker behavior fails toward vanilla when Pusfume is present. It must
not delete or replace Pusfume registrations, force a donor career over it, send
Pusfume-owned resource identities to peers without Pusfume, or make Pusfume
depend on a Tweaker mod. When safe coexistence is not proven, disable only the
conflicting Tweaker feature and report the boundary in the log.

The release matrix for a career/profile/loadout/package/network change is:

1. Tweaker set without Pusfume: existing behavior remains unchanged.
2. Pusfume with the changed Tweaker set: Pusfume remains selectable, spawns,
   equips its loadout, and returns to the Keep without a script/package error.
3. Host and client on the same Pusfume build, with the changed Tweaker mod on
   both peers: career identity, spawn, loadout, and transition remain stable.
4. Pusfume with the changed Tweaker mod absent or disabled: Pusfume still works;
   no Tweaker mod is a required Pusfume dependency.

Pusfume itself currently requires the same Pusfume build on every peer. This
matrix does not claim that an unmodded peer can resolve Pusfume; it verifies that
Tweaker adds no new dependency or failure mode.

---

## Mod 4: modded_progression

**Responsibility:** Re-enable every vanilla progression system in the modded realm (XP, end-of-mission rewards, loot chests, Okri's Challenges, Lohner's Emporium, keep crafting bench), with state persisted locally so the player's real PlayFab account is never touched.

Full design in `modded_progression/PLAN.md`. Key architectural points relevant to siblings:

- **Intercepts `BackendInterface*Playfab` methods**, not `script_data["eac-untrusted"]`. The pipeline runs to the cloud-script call site, gets intercepted there, generates data locally, then calls the same `backend_mirror:*` mutator the success callback would have called. The rest of the game reads from the mirror and cannot tell the difference.
- **PlayFab commits remain blocked** in modded (vanilla behavior at `playfab_mirror_base.lua:2826,2839,2857`). `mp` writes local-only.
- **Persistence:** mirror state is overlaid from VMF settings on game-start, re-serialized on every mutation. Three starting-state options (fresh / level 35 default / level 35 with all cosmetic unlocks).

### Sibling API (planned — not yet wired)

> **Status (verified 2026-06-13, Issue #70.3):** `modded_progression` (`mp`) **exports** this API (`mp.is_unlocked` / `grant_item` / `spend` / `credit` / `has_currency`, defined in `modded_progression.lua`), but **no mod currently consumes it** — a repo-wide grep for `get_mod("mp")` outside `modded_progression/` returns zero hits. The signatures below and the per-mod gating in the next section are the intended design contract, not live behavior. Don't assume an installed `mp` changes any sibling's unlock gating until the consumer side is wired.

```lua
local mp = get_mod("mp")
if mp then
    if not mp.is_unlocked(item_key) then return false end
    mp.grant_item(item_data)
    mp.spend("SM", 250)        -- shillings
    mp.credit("scrap", 5)
    mp.has_currency("orange_dust", 1)
end
```

### Sibling-specific changes when `mp` is installed (planned — see status note above)

- **character_weapon_variants:** `ItemMasterList[variant_key].can_wield` returns `false` until `mp.is_unlocked(variant_key)`. Variants ship locked; earned via loot chests, challenge rewards, Lohner's, mission completion. Without `mp`, current free-unlock behavior remains.
- **cosmetics_tweaker:** Custom illusions, shield options, portraits gate on `mp.is_unlocked(key)`. Without `mp`, current free-unlock behavior remains.
- **crafting_in_modded:** Untouched. Athanor stays free as the sandbox; vanilla-cost crafting at the keep bench is owned by `mp`.
- **chaos_wastes_tweaker, event_tweaker, weapon_tweaker:** No interaction. CW completions naturally credit the un-gated vanilla pipeline; event mutators are upstream of rewards; cross-career unlocks operate at `can_wield` level.

---

## Open Questions

1. **Crafting menu ownership** — does the crafting UI live in character_weapon_variants, cosmetics_tweaker, or a shared UI mod? Simplest: in character_weapon_variants itself.
2. **Icon pipeline** — custom icons per new weapon. Format, resolution, and atlas injection method TBD (see cosmetics_tweaker TODO "Custom illusion icons").
3. **Animation ownership** — if a new weapon needs animation remaps, does character_weapon_variants ship them or delegate to weapon_tweaker? Cleaner if the new mod is self-contained, but duplicates weapon_tweaker's remap infrastructure.
4. **Scope of new weapons** — curated case-by-case. Need to enumerate which cross-character combos are worth building as real items vs. leaving as raw weapon_tweaker unlocks.
5. **Cosmetic curation approach** — lore-friendly by default, hand-picked per character. Only models and illusions matching the current character's aesthetic are shown.

---

## Big Rebalance integration (wt / ct / et + buff_tweaker)

> **[SUPERSEDED 2026-07-07 — bt retired]** `buff_tweaker` (`bt`, Workshop 3730358590) was retired and archived to `_archive/buff_tweaker_v0.1.12-alpha/` (2026-06); `get_mod("bt")` is now always nil. Because every BR sub-feature in wt / ct / et guards on `if not (bt and bt.is_br_active) then return false end`, those sub-features are now permanently INERT (no crash) — they were guarded, NOT stripped. Reconcile to the `bt` row in `MOD_DEPENDENCIES.md`. Content below is preserved for historical/mechanics reference; the present-tense claims about bt "owning"/"hosting" the shared registration describe the pre-retirement state.

Integration of Core's **Cores Big Rebalance** mod (Steam Workshop ID
`2705276978`, internal mod ID `Weapon Balance`) into the user's tweaker mods
as opt-in toggles. Landed 2026-05-21. Refactored 2026-05-21+ to centralize
shared template registration in `buff_tweaker` (mod ID `bt`) — which was
subsequently retired (2026-06), leaving the wt / ct / et sub-features inert
behind their `is_br_active` guards.

Decompiled source archived at
`C:\Users\danjo\source\repos\_big_rebalance_extract\source\` (12 files,
~640KB). Inventory + design + implementation artifacts live alongside.

### Mod split

| Mod | Toggles | Version (at landing) | Owns |
|---|---|---|---|
| `wt` (Tweaker: Weapons) | 114 + master | 0.12.61-dev | `Weapons.*`, `DamageProfileTemplates.*`, weapon function hooks (Flamethrower / Beam / TrueFlight) |
| `ct` (Tweaker: Careers) | 299 + master (`cbr_master_enable_registrations`) | 0.3.0-dev | `TalentBuffTemplates.*`, `BuffTemplates.<career>_*`, passives / ults, `PassiveAbilitySettings.*` |
| `enemy` (Tweaker: Enemies) | 14 + master | 0.5.0-dev | `DamageUtils.stagger_ai` / `calculate_damage` / `ActionShieldSlam._hit` hook rewrites, `BreedTweaks.*`, THP-from-kills buffs |
| `bt` (buff_tweaker) *(RETIRED 2026-06)* | 1 master | scaffolded 2026-05-21; retired 2026-06 | **Was the single shared registration mod.** Pre-registered Big Rebalance buffs / damage profiles / explosion templates on every peer in deterministic sorted order. wt/ct/et's BR sub-toggles all check `(get_mod('bt') or {}):is_br_active()` before applying — with bt retired, `get_mod("bt")` is nil so these checks fail and the sub-features stay inert (guarded, not stripped). |

**SpicyEnemies module dropped entirely** — its 6 forced package preloads
couldn't be safely gated per-user.

### Master toggle pattern

Each of wt / ct / et has its own master (`br_master_enable_registrations`,
ct's is `cbr_master_enable_registrations`). When the user enables it, the
mod patches data tables that reference the BR registrations. Individual
toggles then patch fields within those tables. **All defaults are
`false` — opt-in.**

The shared registration of the canonical 328-entry list lived in
`buff_tweaker` (bt); wt / ct / et toggled sub-features off the `bt` master.
Since bt's retirement (2026-06) that shared registry is gone with the mod, so
the `is_br_active` guard fails on every peer and the BR sub-features stay
inert (guarded, not stripped).

### Known stubs (41 follow-ups)

ct's ult `_run_ability` rewrites and framework hooks (timed-block,
infinite_wounds, dodge_count) shipped as `function() end` placeholders.
Toggles work but no-op until verbatim source is copied.

### How to apply Big Rebalance changes

*(Historical — describes the pre-retirement flow.)* User enabled the `bt`
master + each of the wt / ct / et masters (any combination they wanted), then
individual toggles to taste. With bt retired (2026-06) the `bt` master no
longer exists, so the wt / ct / et BR sub-toggles no-op behind their
`is_br_active` guard regardless of the masters' state.

---

## Cross-mod registration sync (historical / was centralized in `bt`, now retired)

> **State (2026-05-21+, superseded 2026-06):** `buff_tweaker` (`bt`) owned the
> canonical sorted registration list; wt / ct / et no longer shipped per-mod
> registration files. bt was retired 2026-06 (archived to
> `_archive/buff_tweaker_v0.1.12-alpha/`), so that shared registry no longer
> loads and the BR sub-features stay inert behind their `is_br_active` guard.
> The pattern below is preserved for context and for anyone authoring a new
> BR-aware mod that re-hosts the shared registry.

When two or more mods need to inject the **same set** of new
`BuffTemplates` / `TalentBuffTemplates` / `NewDamageProfileTemplates` /
`ExplosionTemplates` (Big Rebalance buffs, custom mutator effects, anything
that lands in `NetworkLookup.buff_templates`), each mod must either:

- **Delegate to a shared registry mod** (preferred — `bt` WAS the canonical
  one for Big Rebalance, now retired; a future BR-aware mod would need to
  re-host this role), OR
- Ship a **byte-identical canonical sorted name list** — NOT just the
  entries that mod cares about.

### Why

At mod load, each mod's master toggle pre-registers names into
`BuffTemplates` + `NetworkLookup.buff_templates` (and equivalents). If
wt's list has 44 entries and ct's has 288:

- Player A (wt + ct + et installed) ends up with one NetworkLookup index
  ordering
- Player B (only ct installed) ends up with a different index ordering
- Host sends `rpc_add_buff(integer_index)` → resolves to a different buff
  per peer → silent buff mismatch or crash

Same failure mode as DEVELOPMENT.md "Gated registration diverges across
peers" — but across mods instead of within one mod.

### Pattern (when shipping a non-`bt`-aware BR mod)

1. Mod ships `<mod>_big_rebalance_registrations.lua` containing the **full
   canonical union** of every new template defined across all
   participating mods.
2. Files are byte-identical except for `local mod = get_mod(...)` and the
   first-line filename comment.
3. Registration code is **idempotent** — each mod's apply function checks
   `if BuffTemplates[name] then continue` before inserting. Two BR-aware
   mods loaded together don't double-register.
4. Canonical reference list lives at
   `_big_rebalance_extract/canonical_BR_REGISTRATIONS.lua` (and in the
   QA report). When adding new entries, update all participating mods
   together.

### Build-time check

When next deploying any BR-aware mod that ships its own registration file,
diff the three `<mod>_big_rebalance_registrations.lua` files — only
filename comment + mod ID local should differ. Anything else means
peer-desync risk.

### Burned

Initial Big Rebalance integration 2026-05-21 — wt shipped 44 entries, ct
shipped 288, et shipped 9. QA agent caught + reconciled to 328 entries
each before any deploy. Two days later (2026-05-21+) the `bt` extraction
landed to eliminate the maintenance burden of keeping three byte-identical
files in sync forever.
