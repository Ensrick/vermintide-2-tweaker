# Engine reference 11 - Backend, PlayFab and loadouts

Scope: PlayFab mirror (read-only data semantics), backend interfaces (items, hero attributes,
statistics), the native saved-loadout system, statistics_db, and how gut / cim / cwv sit on
top of it. Paths: vanilla relative to `C:\Users\danjo\source\repos\Vermintide-2-Source-Code`,
ours relative to the monorepo root. Every claim cites file:line or is marked [unverified].

---

## 1. Architecture map

| File / class | Single responsibility |
|---|---|
| `scripts/managers/backend_playfab/backend_manager_playfab.lua` - `BackendManagerPlayFab` | Top-level manager (`Managers.backend`). Owns signin, creates the mirror (:417), creates all interfaces after mirror ready (:154-181, :392-433), error dialogs, interface-override registries (:312-374), commit passthrough (:933-937). |
| `scripts/managers/backend_playfab/playfab_mirror_base.lua` - `PlayFabMirrorBase` | THE local cache of the player's cloud account: read-only data (:89-90), user data (:117-118), title data (:94), inventory items (:1421-1487), career/loadout data (:3152-3235), plus the commit/diff engine that pushes changes back (:2714-2916). Everything loadout funnels through this one object. |
| `scripts/managers/backend_playfab/playfab_mirror_adventure.lua` - `PlayFabMirrorAdventure` | Concrete runtime subclass for players. Picks the characters-data key: `characters_data` (adventure) vs `vs_characters_data` (versus) (:26-33), drives `verifyCareerLoadouts` / versus setup (:38-119), weaves loadout check (:171-200). |
| `playfab_mirror_dedicated.lua` | Dedicated-server mirror variant. Out of scope for our P2P users (gut hooks the Adventure subclass for this reason, `gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_native_loadouts.lua:35-38`). |
| `scripts/managers/backend_playfab/playfab_request_queue.lua` | Serializes CloudScript (`ExecuteCloudScript`) and client-API requests; timeout -> `Managers.backend:request_timeout()` (playfab_mirror_base.lua:1801-1818). |
| `backend_interface_item_playfab.lua` - `BackendInterfaceItemPlayfab` | Item/loadout facade over the mirror. Caches `_items`, `_loadouts`, `_career_loadouts`, `_bot_loadouts`, `_default_loadouts` (:7-23), rebuilt from the mirror on `_refresh` when `_dirty` (:37-54). Equip write = `set_loadout_item` (:635-670). |
| `backend_interface_hero_attributes_playfab.lua` - `BackendInterfaceHeroAttributesPlayFab` | XP / prestige / selected-career facade. Reads read-only keys like `empire_soldier_experience` (:7-26, :56-60); per-character `career` / `bot_career` live INSIDE characters_data and are written via `mirror:set_career_read_only_data(hero, attr, value, nil, false)` (:27-30, :95-109). |
| `backend_interface_statistics_playfab.lua` - `BackendInterfaceStatisticsPlayFab` | Stats bridge: loads `loadPlayerStatistics` into `mirror:set_stats` (:11-30), snapshots dirty stats from `statistics_db` (:75-101), builds the `savePlayerStatistics3` request the commit sends (:140-159). |
| `backend_interface_talents_playfab.lua` | Talents facade; talent strings are just the `"talents"` key of a loadout row: `mirror:get_character_data(career, "talents")` (:37, :73) / `mirror:set_character_data(career, "talents", str, false, idx)` (:331). |
| `scripts/managers/backend/backend_utils.lua` - `BackendUtils` | PLAIN-TABLE helper layer everything gameplay-side calls: `get_loadout_item_id` (:14), `set_loadout_item` (:22), `get_loadout_item` (:30), `get_item_from_masterlist` (:63), power-level math (:84-134). Routes through `Managers.backend:get_loadout_interface_by_slot` (:15, :23) - the interface-override seam. |
| `scripts/managers/backend/statistics_database.lua` - `StatisticsDatabase` | In-session stat store (`Managers.player:statistics_db()`). Registers per-player stat trees seeded from backend stats (:109-162), increments/sets (:381-491), RPC receivers for cross-peer stat sync (:582-663), and `apply_persistant_stats` / `generate_backend_stats` for the save round-trip (:714, :372). |
| `scripts/managers/backend_playfab/backend_interface_crafting_playfab.lua` | Vanilla crafting recipes (salvage/craft/reroll) as CloudScript calls; cim replaces its recipe execution locally (`crafting_in_modded_dev/.../standard_forge.lua:433-449`). |
| OURS: `gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_native_loadouts.lua` | Modded-realm-only replacement STORE for the native saved-loadout system. Hooks the mirror's 3 read + 5 write methods; official `_career_data` is never mutated in modded (design block :16-47). |
| OURS: `crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev.lua` | Craft persistence (`_forged_weapons` save layer :340-406) + boot re-injection into the mirror via `add_item` (`_athanor_inject_item` :5270-5348). Its OWN loadout persistence is force-disabled - gut owns loadouts (:729-751). |
| OURS: `character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua` | Registers variant items with synthetic bids `<key>_NNN` via MoreItemsLibrary (:9491-9530); wire-safety substitutions (:10351-10447); husk base+career re-key (:10044-10113). |

Realm signal: `script_data["eac-untrusted"]` - the backend itself stamps `realm = "modded"` /
`"official"` from it (backend_manager_playfab.lua:66-70). gut's `_in_modded_realm()` reads the
same flag (`_gut_native_loadouts.lua:193-196`).

---

## 2. Lifecycle and data flow

### 2.1 Signin -> mirror -> interfaces (order matters for hook installs)

1. `BackendManagerPlayFab:signin` creates `_backend_signin` (backend_manager_playfab.lua:81-128).
2. `_update_state` creates the mirror from the signin result once authenticated (:414-421) -
   `PlayFabMirrorAdventure:new(signin_result)`.
3. `PlayFabMirrorBase.init` seeds `_read_only_data` + `_read_only_data_mirror` (a clone -
   the DIFF baseline), `_user_data` + `_user_data_mirror` (playfab_mirror_base.lua:50-123),
   then chains ~15 sequential CloudScript calls (verifyAccountData -> migrate ->
   updateDLCOwnership -> ... -> GetUserInventory -> request_characters), each incrementing
   `_num_items_to_load` (:344-1487).
4. Inventory: `inventory_request_cb` fills `_inventory_items[backend_id] = item`, filtering
   cosmetics/skins and locked-DLC items out (:1421-1464), then materializes "fake" items
   (skins / cosmetics / poses) with GUID bids into BOTH `_inventory_items` and
   `_fake_inventory_items` (:1478-1480, :2383-2403).
5. Characters: `request_characters` -> `verifyCareerLoadouts` (playfab_mirror_adventure.lua:38-119)
   -> `_verify_dlc_careers` -> `_setup_careers` decodes the `characters_data` JSON into
   `_career_data[career_name][i] = {slot_melee=bid, ..., talents=str}` +
   `_career_loadouts[career_name] = selected_index` + `_characters_data` (+ `_mirror` clones)
   (playfab_mirror_base.lua:3152-3235).
6. During `_setup_careers`, every loadout slot is VERIFIED: a slot whose value is not in
   `_inventory_items` / unlocked-cosmetics / poses is a "broken slot" (:1579-1659); items
   also get can_wield / slot-type / rarity checks (:1661-1721; versus additionally rejects
   non-`default` rarity :1620-1629). Any broken slot triggers CloudScript `fixCareerData`,
   which REPLACES gear with `character_starting_gear` and writes it back to read-only data
   (:3277-3344). This is the engine mechanism that turned leaked modded ids into the
   "Blacksmith greatsword" on official (issue #402 symptom).
7. `mirror:ready()` = `_inventory_items and _num_items_to_load == 0` (:1789-1791). Only then
   does the manager create the interfaces (backend_manager_playfab.lua:404-421). Hence every
   mod hook on interface INSTANCES must install deferred (gut `_install_bu_capture`
   `_gut_native_loadouts.lua:425-460`; cim `_install_backendutils_capture`
   crafting_in_modded_dev.lua:1559-1576).

### 2.2 Read-only data semantics ("read-only" = client cannot commit it directly)

- `get_read_only_data(key)` returns scalar-coerced values; only boolean/number/string allowed
  (playfab_mirror_base.lua:29-33, :2145-2152). `set_read_only_data(key, value, set_mirror)`
  writes the LOCAL cache; `set_mirror=true` also updates `_read_only_data_mirror`, i.e. "the
  server already knows this" - no diff, nothing pushed (:2154-2173).
- `set_mirror=false/nil` is the ONLY way a read-only value becomes "dirty". But the commit
  does NOT walk `_read_only_data` generically: the only read-only payload it builds is
  `keep_decorations` + the characters-data diff (:2875-2909). Everything else read-only is
  updated exclusively by CloudScript RESPONSES calling `set_read_only_data(..., true)`.
- Guard rail: writing `characters_data`/`vs_characters_data` with `set_mirror` falsy while
  `debug_characters_data_unsafe_write` is set Crashifies "Unsafe write to readonly data"
  (:2154-2158); the flag is armed during mechanism switches (playfab_mirror_adventure.lua:18).

### 2.3 The commit/diff engine (what can ever reach the cloud)

`commit(skip_queue, cb)` queues (delay = `_commit_limit_total * 5` s, :2762-2774) then
`_commit_internal` builds the payload (:2801-2916):

| Payload | Built from | EAC-gated? |
|---|---|---|
| Stats (`savePlayerStatistics3`) | `statistics` interface `get_stat_save_request` | YES - skipped when `script_data["eac-untrusted"]` (:2826-2837) |
| Weave user data | weaves interface dirty data | YES (:2839-2855) |
| Equipped weapon pose skins | items interface `_dirty_weapon_pose_skins` | YES (:2857-2873) |
| `keep_decorations` + characters_data (`updateHeroAttributes`) | `_check_career_data(_career_data, _career_data_mirror)` diff (:2875-2909) | **NO** |
| User data (`UpdateUserData` client API) | `_user_data` vs `_user_data_mirror` diff (`_commit_user_data` :2111-2135) | **NO** |

`_check_career_data` (:3409-3628) compares `_characters_data` vs its mirror (selected
career/bot/loadout-index changes, :3422-3478) and each `_career_data[career][i][slot]` vs the
mirror (:3480-3549); any mismatch lands in `dirty_hero_data` and is pushed. **The
characters-data and user-data pushes run in the modded realm too** - this is why gut's
isolation works by never letting `_career_data`/`_characters_data` mutate in modded
(`_gut_native_loadouts.lua:24-41`), not by blocking commits.

Success path re-mirrors the server's authoritative response (:2950-3014); `dirtify_interfaces`
runs after every finished commit (:1856-1859).

### 2.4 Item identity: bid -> key -> data (where a mod item id degrades)

1. **bid -> item**: `_inventory_items[backend_id]` is the ONLY registry.
   `PlayFabMirrorBase._update_data` stamps every item: `item.backend_id = bid`,
   `item.key = item.ItemId`, `item.data = ItemMasterList[item.ItemId]` and decodes
   CustomData properties/traits/power_level/rarity/skin (playfab_mirror_base.lua:1723-1787).
   `item.data` is a SHARED reference to the IML entry, not a clone (bit us: cim's
   `mechanisms = nil` clear affects every item of that key, crafting_in_modded_dev.lua:438-451).
2. **interface read**: `get_item_from_id(bid)` = `get_all_backend_items()[bid]` = `_items[bid]`
   after a dirty `_refresh` (backend_interface_item_playfab.lua:384-389, :431-437). No
   validation beyond table presence. With game-mode-specific items active, `_items` is a
   FROZEN CLONE of the mirror table (:68-73) - the gut #387 divergence source.
3. **loadout read**: `BackendUtils.get_loadout_item(career, slot)` = `get_loadout_item_id`
   (mirror `get_character_data` under the hood, :512-538) then `get_item_from_id`
   (backend_utils.lua:30-46). `BackendUtils.get_item_from_masterlist(bid)` returns a CLONE of
   `item.data` with only `backend_id` attached - per-instance CustomData (traits, skin,
   properties) is DROPPED here (backend_utils.lua:63-74).
4. **spawn**: `SimpleInventoryExtension` gathers items via `BackendUtils.get_loadout_item`
   (simple_inventory_extension.lua:384) and equipment slots carry `item_data` = the
   masterlist-shaped table whose `.name` is the item KEY.
5. **wire (the hard degrade)**: every equipment RPC encodes
   `item_id = NetworkLookup.item_names[item_data.name]` +
   `weapon_skin_id = NetworkLookup.weapon_skins[skin or "n/a"]` - the backend id NEVER
   crosses the wire. Send sites: `game_object_initialized`
   (simple_inventory_extension.lua:255-264), `_spawn_resynced_loadout` (:1443-1464),
   gear_utils.lua:483, inventory_system.lua:230-238/:335-337. Loadout-panel sync likewise
   sends `NetworkLookup.item_names[item.key]` + rarity + properties, no bid
   (scripts/helpers/loadout_utils.lua:13-43).
6. **receiver**: `InventorySystem.rpc_add_equipment` decodes
   `NetworkLookup.item_names[item_name_id]` and hands the husk a plain item NAME
   (inventory_system.lua:282-307); `LoadoutUtils.create_loadout_item_from_rpc_data` rebuilds a
   pseudo-item with `item.data = ItemMasterList[item_key]` (loadout_utils.lua:70-88). The husk
   therefore always resolves the BASE ItemMasterList entry (BUG_CLASSES.md 27).

**Issue #474 mechanism 3, precisely**: a cwv variant is a clone of its base IML entry -
`_build_entry` does `table.clone(base, true)` and DELIBERATELY keeps `entry.name` = the base
weapon key (clobbering it crashed `ItemMasterList[item.name]` fallback lookups, see
character_weapon_variants.lua:9069-9084 + the `cwv_variant` marker :9085). So on the wire the
musket encodes `item_name = es_handgun` (step 5 uses `item_data.name`) plus the cwv skin key;
the receiving peer resolves base-handgun item_data and unit paths (the NetworkLookup
inventory_packages alias is forward-only by design, character_weapon_variants.lua:5210-5232),
and the husk re-key map skips natively-wieldable (base, career) pairs by design
(:10065-10106) - es_mercenary can natively wield es_handgun, so the musket husk never
re-keys. The identity that DOES survive the wire is the skin key; the dispatched fix re-keys
husk mesh+transform from skin->def first (issue #474 comment; memory
`reference_vt2_husk_base_career_rekey`).

### 2.5 Native saved loadouts: what is cloud, what is local

- Loadout CONTENTS + the roman-numeral selected index are CLOUD data: rows live in
  `characters_data[profile].careers[career][i]`, selection in
  `characters_data[profile].loadouts[career_index]`; `set_loadout_index` / `add_loadout` /
  `delete_loadout` all re-encode characters_data into read-only data and `dirtify_interfaces`
  (playfab_mirror_base.lua:1968-2068). Writes to a row go through `set_character_data`
  -> `_career_data` (:1928-1942) -> `set_career_read_only_data` -> `_characters_data` +
  re-encode (:3630-3653). The cloud push is the `_check_career_data` diff (2.3).
- LOCAL (per-machine `PlayerData.loadout_selection`, never cloud): the bot-equipment
  designation `bot_equipment[career] = loadout_index` (backend_interface_item_playfab.lua:128-160)
  and the "default loadout" override selection per mechanism (:228-255). Bots read
  `get_bot_loadout`/`get_loadout_by_career_name(career, is_bot)` (:461-510).
- Equip flow (menu): `HeroViewStateOverview` -> `BackendUtils.set_loadout_item(bid, career,
  slot)` (backend_utils.lua:22-28) -> `get_loadout_interface_by_slot(slot):set_loadout_item`
  -> `BackendInterfaceItemPlayfab.set_loadout_item` validates the bid exists and is not
  `magic` rarity, rewrites cosmetic/pose ids from bid to `override_id or ItemId` (a KEY, not a
  bid), then `mirror:set_character_data(career, slot, item_id, nil, optional_index)`
  (:635-670).

### 2.6 statistics_db round trip

Session: `StatisticsDatabase.register(id, category, backend_stats)` builds the per-player stat
tree, seeding `persistent_value` from backend stats (statistics_database.lua:109-162).
Gameplay increments via `increment_stat` etc. mark entries `dirty` (:381-447). Cross-peer sync
is RPC-based (`rpc_increment_stat`/`rpc_sync_statistics_number`..., :582-663; receivers are
dynamically dispatched and hookable, memory `reference_vt2_rpc_dispatch_dynamic_hookable`).
Save: commit calls `statistics` interface `save()` only when `in_hub_level`
(playfab_mirror_base.lua:2818-2822), which flattens + filters `dirty` stats with a
`database_name` (backend_interface_statistics_playfab.lua:40-101) into `savePlayerStatistics3`;
on ack, `clear_dirty_flags` + `statistics_db:apply_persistant_stats()` fold session values
into persistent (:3017-3035; statistics_database.lua:714). In the modded realm this entire
push is EAC-gated off (2.3) - vanilla progression is frozen, which is what `mp` exists to
work around (repo CLAUDE.md, Mod Directory).

---

## 3. Hookable seams (and the safe pattern for each)

| Seam | Pattern | Trap |
|---|---|---|
| `PlayFabMirrorAdventure` read/write methods (`get_character_data` :1909, `get_career_loadouts` :1944, `has_loadout` :1921, `set_character_data` :1928, `set_career_read_only_data` :3630, `set_loadout_index` :1968, `add_loadout` :2036, `delete_loadout` :1994) | String-form `mod:hook("PlayFabMirrorAdventure", ...)`. This is the SMALLEST provable loadout surface - every interface (items, talents, LA clones) funnels through it (`_gut_native_loadouts.lua:16-41`). To block a write, capture and DO NOT call `func` - the commit diff then finds nothing dirty (2.3). | Hook the CONCRETE subclass, never `PlayFabMirrorBase`: class.lua copies parent methods into the child at definition time, so a base hook misses the live instance (foundation class.lua:51-57 per `_gut_native_loadouts.lua:35-38`). Dedicated servers use a different subclass. |
| `BackendUtils.set_loadout_item` / `get_loadout_item` (backend_utils.lua:22/:30) | TABLE-form hook (plain table), installed DEFERRED after `Managers.backend:get_interface("items")` succeeds. This is the stable OUTER entry the hero view calls and the only capture point that still fires when Loremaster's Armoury swaps in a cloned interface (cim burn 2026-05-30; gut #353). GUT resolves cosmetic bids through that selected interface and stores the same `override_id or ItemId` value vanilla derives at `backend_interface_item_playfab.lua:656-663`. | `BackendInterfaceItemPlayfab` class hooks MISS LA-cloned-instance dispatch; conversely `BackendUtils` never sees restore-path direct interface calls - keep the mirror hooks too. Never save an unresolved cosmetic's transient bid as a guess. Do NOT hook `BackendUtils.can_wield_item` (not hookable; repo CLAUDE.md "Hooking"). |
| `BackendInterfaceItemPlayfab` getters (`get_item_from_id` :384, `get_filtered_items` :627, `set_loadout_item` :635) | String-form class hook; fine for read shaping (cosmetics_tweaker pattern). After mutating mirror state call `Managers.backend:dirtify_interfaces()` (backend_manager_playfab.lua:211-219) - it is a LOCAL cache invalidation, not a network push. | NEVER call `get_item_from_id`/`get_all_backend_items` from INSIDE a mirror read hook: `_dirty` -> `_refresh` -> mirror read -> your hook -> unbounded recursion -> 1 GiB heap crash (gut v0.2.173 burn, `_gut_native_loadouts.lua:359-367`). Inside mirror hooks use raw field reads only (`iface._items`, `mirror._inventory_items` :2189). |
| Loadout interface override registry: `Managers.backend:add_loadout_interface_override(name, iface_by_slot)` + `set_loadout_interface_override(name)` (backend_manager_playfab.lua:312-341) | ENGINE-NATIVE seam to reroute whole slots to another interface (weaves use it; `BackendUtils` consults it on every loadout read/write :14-27). A mod-owned interface object per slot is an alternative to hooking for whole-mode loadout swaps. Same idea for talents (:343-371) and total power level (:373-390). | The override applies by SLOT NAME for ALL careers; it is mode-global, not per-career. |
| Interface replacement: `Managers.backend._interfaces[name] = <object>` | Engine-sanctioned precedent: tutorial and benchmark swap `items`/`hero_attributes` wholesale and restore on stop (backend_manager_playfab.lua:250-310). `mp` intercepts interfaces this way [unverified - mp scaffolding]. | Every interface must answer `ready()` truthfully or `profiles_loaded` never flips (:943-979). |
| Adding items: `mirror:add_item(backend_id, {ItemId=key, ItemInstanceId=bid, CustomData=...})` (playfab_mirror_base.lua:2494-2545) | The correct injection point for synthetic inventory (cim `_athanor_inject_item` :5306-5313). CustomData strings are cjson-decoded by `_update_data`. Follow with `dirtify_interfaces`. | `add_item` indexes `ItemMasterList[item.ItemId]` raw (:2504) - IML has a Crashify `__index`; pre-check `rawget(ItemMasterList, key)` (cim :5274-5283). Weapon-skin/cosmetic/pose ItemIds get REROUTED to the fake-item path and a different bid comes back (:2499-2524). `skip_mark_as_new` otherwise spams new-item markers. |
| Item mutation: `mirror:update_item(bid, item)` / `update_item_field` (:2557-2574) | Used by cim's apply/extract-skin synth (standard_forge.lua:527-556). | Both `fassert` if the bid is unknown (:2561, :2569). |
| `LoadoutUtils.sync_loadout_slot` (loadout_utils.lua:13) | TABLE-form hook (`LoadoutUtils = LoadoutUtils or {}` plain table). THE wire-safety choke point for loadout-panel sync: swap non-vanilla `item.key`/`rarity` for wire-stable vanilla values on a SHADOW copy, then call `func` (cwv :10381-10408; cim rarity coercion :764-806). | Wire-safety substitutions must be UNCONDITIONAL, never behind a feature toggle - v0.8.15 gated the rarity rewrite and crashed every vanilla client (BUG_CLASSES.md 31; memory `reference_vt2_wire_safety_never_toggle_gated`). |
| `StatisticsDatabase` methods + RPC receivers (statistics_database.lua:381-663) | String-form class hooks; receivers ARE hookable because NetworkEventDelegate dispatch is dynamic (memory `reference_vt2_rpc_dispatch_dynamic_hookable`). | In modded realm the backend save is EAC-gated off (2.3); local stat writes are session-only there. |

---

## 4. Traps and crash classes

- **Husk resolves BASE item_data** - backend id and mod_data never cross the wire (2.4). Any
  owner-side logic keyed on `item.backend_id`/`item_data.mod_data` is structurally blind on
  remote peers. BUG_CLASSES.md 27; issues #392/#474.
- **Wire indices are peer-local for mod-appended NetworkLookup keys** - `#tbl + 1` appends
  (cwv :9556-9560 [item_names], :7975-7979 [weapon_skins]) differ per peer and are UNDEFINED
  on peers without the mod; cold decode hits the strict `__index` fatal
  (network_lookup.lua:2362/2521 per cwv comments :10357-10365, :10410-10416). Sender-side
  substitution must be unconditional. BUG_CLASSES.md 31; issues #278/#371/#424.
- **`get_item_from_id` from inside a mirror read hook = unbounded recursion** (gut v0.2.173;
  `_gut_native_loadouts.lua:359-367`). Related: memory `reference_vt2_lua_heap_1gib_crash`.
- **Signin-time loadout verification is destructive**: an id not resident in
  `_inventory_items` at `_setup_careers` time is a "broken slot" and CloudScript `fixCareerData`
  REPLACES it with starting gear (playfab_mirror_base.lua:1579-1721, :3277-3344). Mod ids
  registered later than backend init (cim crafts, MIL items, LA instances) MUST therefore
  never sit in OFFICIAL characters_data (issue #402), and modded-side stores must never
  destructively sanitize "unresolvable right now" ids (gut burns 2026-07-02 #1/#2,
  `_gut_native_loadouts.lua:62-77`).
- **`_check_career_data` on a career missing from `_career_data` = deliberate crash dump**
  ("You will crash now", playfab_mirror_base.lua:3551-3598). Never remove career tables from
  the live mirror; gut serves reads instead of mutating.
- **EAC gating is asymmetric** (2.3): stats/weaves/poses never push from modded, but
  characters_data (`updateHeroAttributes`) and user data DO. "Modded realm" is not "offline";
  isolation must be enforced by keeping the diff clean, not by assuming no commits happen.
- **`ItemMasterList` / `NetworkLookup.*` strict `__index`** - always `rawget` cold reads
  (BUG_CLASSES.md 4; cim :5274-5283, cwv :9538-9544).
- **`item.data` is shared with IML** - mutating it (mechanisms, can_wield) changes every item
  of that key AND the master list (crafting_in_modded_dev.lua:438-451). Clone before diverging.
- **Frozen `_items` clone under game-mode items**: `get_item_from_id` and mirror
  `_inventory_items` can disagree while `_dirty` or when `_active_game_mode_specific_items`
  is set (backend_interface_item_playfab.lua:68-75) - the #387 stuck-weapon signature
  (`_gut_native_loadouts.lua:339-357`).
- **Empty weapon slots fatal at spawn** ("Tried to wield default slot slot_melee ... no
  weapon") - never serve nil for slot_melee/slot_ranged (gut v0.2.172 burn,
  `_gut_native_loadouts.lua:81-83`).
- **Versus mirror**: mechanism switch re-keys characters data (`vs_characters_data`) and arms
  the unsafe-write Crashify (playfab_mirror_adventure.lua:16-36); loadout hooks must
  discriminate on `mirror._characters_data_key` (gut `_mirror_mode`,
  `_gut_native_loadouts.lua:229-234`) or corrupt Versus.
- **Loadout-preview UI has no nil-guard on equipment items**
  (`_populate_context_menu_loadout` equipment loop per gut :796-826) - any store serving
  possibly-unresolvable gear ids must sanitize the PREVIEW copy (never the store) or pcall.
- **`hero_attributes:set` on `career`/`bot_career` writes characters_data**, not a plain
  read-only key (backend_interface_hero_attributes_playfab.lua:95-109) - realm-isolation
  audits must include it (it reaches `set_career_read_only_data` with career=nil).

---

## 5. Implications for our mods (concrete)

### 5.1 gut native loadouts (`_gut_native_loadouts.lua`)

The mirror-hook architecture is engine-correct (sole choke points verified in 2.3/2.5; the rt
check pins all five write hooks, :1209-1224). Remaining friction:

1. **FIXED (gut_dev v0.2.217-dev, shipped 2026-07-12): official fallback no longer passes a
   STORE-space index to the official read.** Both `get_character_data` fallback sites route
   through `_official_gear_fallback` (`_gut_native_loadouts.lua`), which passes a `nil` index
   (vanilla resolves the official SELECTED row, playfab_mirror_base.lua:1911) and, for weapon
   slots only, last-resorts to `get_default_loadouts` row 1 (:1955-1966) before serving nil
   with a loud printf. rt check `native_loadouts_fallback_index_translation` pins the
   translation on a synthetic store row.
2. **Career-nil `set_career_read_only_data` passes through in modded** (:711-714). That is
   the hero-attributes `career`/`bot_career` write (backend_interface_hero_attributes_playfab.lua:100-101),
   which lands in `_characters_data`, diffs dirty (playfab_mirror_base.lua:3435-3441) and
   pushes via the un-gated `updateHeroAttributes` (2.3). Values are benign (career selection),
   but if #402's isolation is meant to be absolute, capture these too (store
   `selected career` modded-side and no-op vanilla); at minimum document the exception.
3. **Post-scrub commit is deterministic.** After at least one verified replacement is
   written, `/scrub_official_loadouts apply` calls `Managers.backend:commit(true, cb)`
   exactly once and reports both the returned commit id and callback status. Only the
   engine's `success` status is accepted as committed; `commit_error`, a missing mirror,
   and a thrown or unavailable backend interface are reported as local-only repairs rather
   than false cloud success (`backend_manager_playfab.lua:933-937`;
   `playfab_mirror_base.lua:1842-1868, :2703-2753`). Report-only, clean, and zero-repair
   runs never request a commit.
4. **Bot designation store vs engine local store**: gut skips the `PlayerData.loadout_selection`
   write and keeps `bot_index` modded-side (:765-794) - correct, since PlayerData is
   realm-shared. Keep the `refresh_bot_loadouts` overlay hook as the ONLY bot read path;
   vanilla also validates `has_loadout(career, bot_index)` (backend_interface_item_playfab.lua:143-146),
   which gut's has_loadout hook already answers from the store (:567-577).

**Exit-snapshot owner boundary (#273).** `BackendUtils.get_loadout_item_id` is not inherently a
durable-store read: it dispatches through `get_loadout_interface_by_slot` [src:
`backend_utils.lua:14-28`; `backend_manager_playfab.lua:329-341`]. Deus assigns melee/ranged to
the `deus` interface while cosmetics remain on `items` [src:
`backend_interface_deus_base.lua:7-14`], then resets and grants generated weapon instances at
run setup [src: `deus_mechanism.lua:1120-1175`]. Consequently an exit backstop must compare the
active per-slot interface by identity with the durable `items` interface *before* reading. A
foreign or unknown owner is a non-destructive skip; an items-owned cosmetic remains eligible.
Issue #273's 2026-07-20 log proves the failure signature: successive `[gut:persist] ... -> store`
lines captured changing `cwv_es_maul<generated>` ids during the run, those ids became
`official-fallback-resolve-no` after `old_loadout: deus new_loadout: nil`, and the player spawned
with the prior native weapon. This is BUG_CLASSES class 73, not a renderer/husk identity fault.

### 5.2 cim (`crafting_in_modded_dev`)

5. **Craft injection is on the right seam** (`mirror:add_item` + dirtify,
   :5306-5347). Two cleanups: (a) `_forge_create_item` hand-rolls JSON strings with
   `tostring(v)` (:484-502) while the Athanor path uses `cjson.encode` (:5300-5303) - unify
   on cjson (a string-valued property would emit invalid JSON). (b) The dormant loadout
   capture/restore machinery (:729-751 force-off) is dead weight now that gut owns loadouts -
   excise per the comment's own plan; its `BackendUtils` capture still installs a hook that
   does nothing.
6. **Salvage leaves dangling bids in gut's store.** `synth.salvage` unregisters cim's own
   layers (`standard_forge.lua:508-520` -> `mod._cim_clear_modded_loadout_for_bid`,
   crafting_in_modded_dev.lua:1121-1165) but gut's `native_loadouts` rows keep the salvaged
   bid forever, silently falling back per-read (by design non-destructive). Add a cross-mod
   notification (cim calls a gut-exposed `clear_bid(bid)` that removes exact-id matches from
   store rows) so stores converge instead of masking.

### 5.3 cwv / cim crafted-item identity (issue #474 mechanism 3)

7. **The wire identity of every cwv/cim item is (base key, skin key) - own that contract.**
   Degrade points, in order: `entry.name` kept = base key by design
   (character_weapon_variants.lua:9069-9084); `BackendUtils.get_item_from_masterlist` drops
   CustomData (backend_utils.lua:63-74); the RPC encodes `item_names[item_data.name]` +
   `weapon_skins[skin]` only (simple_inventory_extension.lua:255-264, :1443-1464;
   loadout_utils.lua:21-26). Consequence: husk-side variant resolution must be keyed
   PRIMARILY on the skin key (positively identifies the variant instance) with the
   (base, career) map as skinless fallback - the dispatched #474 fix; the can_wield-excluded
   map alone can never cover natively-wieldable pairs (:10065-10106).
8. **Skin wire-null coverage gap [PLAUSIBLE - verify against the #371 axis map].** cwv nulls
   its NetworkLookup.weapon_skins keys only on `game_object_initialized` (:10424-10447), but
   `_spawn_resynced_loadout` sends `weapon_skin_id` on every mid-session re-equip
   (simple_inventory_extension.lua:1443-1457) and the #474 client log proves cwv skin keys do
   cross that path. Both #477 peers ran cwv so decode succeeded; a NON-cwv peer cold-decoding
   the appended index is the BUG_CLASSES 31 CTD. If not already covered, hook the resync path
   with the same null/restore.
9. **cim crafts of cwv items are ordering-sensitive**: boot re-injection skips unknown IML
   keys (crafting_in_modded_dev.lua:5274-5283) because cwv registers on
   `StateInGameRunning.on_enter` (`_auto_register_all`, character_weapon_variants.lua:9453).
   gut's tri-state resolver absorbs the same lateness read-side (`_gut_native_loadouts.lua:62-77`).
   Any new consumer of crafted bids must treat "unresolvable now" as "retry later", never
   "delete".

### 5.4 Statistics

10. Nothing of ours hooks statistics today; if `mp` re-enables progression it should reuse the
    engine round trip (interface `save_explicit` + `generate_backend_stats` + persist the
    resulting `backend_stats` table itself, backend_interface_statistics_playfab.lua:103-127,
    statistics_database.lua:372-379) rather than mirror internals - the save/apply pair is the
    documented invariant point (`apply_persistant_stats` only after ack, :133-138 / :714).
