--[[
_adventure_pool — Chaos Wastes map pool customization.

Two things happen here (gated on inject_adventure_maps master toggle):

  1. Adventure missions are injected into the CW TRAVEL/SIGNATURE pools as
     `<adv_key>_<theme>_path1` permutation entries that point at the adventure
     bundle but flag game_mode/mechanism = "deus".

  2. Vanilla CW scenarios that the user disables are removed from those same
     pools. After filter+injection, a POOL FLOOR (#457/#487) handles underflow: a
     TRAVEL/SIGNATURE pool holding fewer distinct ENABLED missions than the graph
     solver needs has its ENABLED missions DUPLICATED under `_dupN` suffix keys, so an
     underflowed run REPEATS the missions the user chose (we never backfill levels he
     disabled). A pool the user empties of ALL enabled missions has nothing to clone,
     so that pool alone falls back to its vanilla contents (with a chat notice) rather
     than deadlock the graph generator into a load freeze.

Availability UI (#457 "Revamp Mission Availability"): each DLC / the Helmgart
campaign / the CW scenarios / the event missions is a MASTER toggle
`enable_group_<id>`; multi-mission groups expand to an advanced per-mission list.
A mission is enabled iff its group master is ON and (the group is single-mission, or
its per-mission toggle is ON). See build_master_widget / enabled_missions.

ARENA / SHOP / finale arenas / Belakor's Temple / Citadel of Eternity are NEVER
touched — those node types are out of scope.

Catalog format: every entry has `key` (LevelSettings key) and `name` (user-facing
display name shown next to the toggle in VMF settings).
]]

local mod = get_mod("ct_dev")

local _M = {}

-- =====================================================================
-- Catalogs
-- =====================================================================

-- Vanilla CW scenarios that may roll as TRAVEL/SIGNATURE nodes. NOT including
-- finale arenas (arena_ruin/cave/ice/citadel/belakor) or shop nodes (shop_*).
-- Display names sourced from `<key>_title` via /dump_adventure_names 2026-05-13.
_M.CW_SCENARIOS = {
    -- TRAVEL
    { key = "pat_forest",   name = "The Forbidden Trail",  pool = "TRAVEL" },
    { key = "pat_town",     name = "Grimblood's Stronghold", pool = "TRAVEL" },
    { key = "pat_mountain", name = "Pinnacle of Nightmares", pool = "TRAVEL" },
    { key = "pat_mines",    name = "Bel'sha'ziir's Mine",  pool = "TRAVEL" },
    { key = "pat_tower",    name = "Holseher's Tower",     pool = "TRAVEL" },
    { key = "pat_bay",      name = "Slaughter Bay",        pool = "TRAVEL" },
    -- SIGNATURE
    { key = "sig_mordrek",  name = "Count Mordrek's Fortress", pool = "SIGNATURE" },
    { key = "sig_gorge",    name = "The Foetid Gorge",         pool = "SIGNATURE" },
    { key = "sig_volcano",  name = "Cinder Peak",              pool = "SIGNATURE" },
    { key = "sig_snare",    name = "The Pit of Reflections",   pool = "SIGNATURE" },
    { key = "sig_crag",     name = "The Lost City of Marakza", pool = "SIGNATURE" },
}

_M.CW_SETTING_PREFIX = "enable_cw_"

-- Adventure missions grouped by DLC. Display names sourced from
-- LevelSettings[<key>].display_name via /dump_adventure_names 2026-05-13.
-- Order here drives toggle display order in VMF settings. Helmgart first (original 13),
-- then each DLC by release order. Each group's `display_name` becomes its master-toggle
-- label `enable_group_<id>` (built in build_loc_entries); #457.
-- `icon` field maps each mission to one of the 11 vanilla CW node textures shown
-- on Olesya's map. Pulled from deus_level_settings.lua texture_id values: mountain,
-- volcano, tower, bay, crag, snare, mordrek, gorge, mines, forest, town, temple.
-- (twitch_icon_shrine is reserved for SHOP nodes — we don't use it.) Each adventure
-- mission gets the icon whose theme most closely matches its setting.
_M.MISSION_GROUPS = {
    {
        id = "helmgart",
        display_name = "Helmgart (Base Game)",
        missions = {
            -- Listed in roughly the campaign order in vanilla Helmgart.
            { key = "skittergate",       name = "The Skittergate",         icon = "temple" },
            { key = "bell",              name = "The Screaming Bell",      icon = "tower" },
            { key = "skaven_stronghold", name = "Into the Nest",           icon = "mines" },
            { key = "ground_zero",       name = "Halescourge",             icon = "town" },
            { key = "elven_ruins",       name = "Athel Yenlui",            icon = "forest" },
            { key = "fort",              name = "Fort Brachsenbrücke",     icon = "town" },
            { key = "ussingen",          name = "Empire in Flames",        icon = "town" },
            { key = "mines",             name = "Hunger in the Dark",      icon = "mines" },
            { key = "catacombs",         name = "Convocation of Decay",    icon = "mines" },
            { key = "military",          name = "Righteous Stand",         icon = "town" },
            { key = "warcamp",           name = "The War Camp",            icon = "forest" },
            { key = "nurgle",            name = "Festering Ground",        icon = "gorge" },
            { key = "farmlands",         name = "Against the Grain",       icon = "forest" },
        },
    },
    {
        id = "back_to_ubersreik",
        display_name = "Back to Ubersreik",
        missions = {
            { key = "magnus",        name = "The Horn of Magnus",          icon = "tower" },
            { key = "cemetery",      name = "Garden of Morr",              icon = "temple" },
            { key = "forest_ambush", name = "Engines of War",              icon = "forest" },
        },
    },
    {
        id = "shadows_over_bogenhafen",
        display_name = "Shadows Over Bögenhafen",
        missions = {
            { key = "dlc_bogenhafen_slum", name = "The Pit",               icon = "town" },
            { key = "dlc_bogenhafen_city", name = "The Blightreaper",      icon = "town" },
        },
    },
    {
        id = "karak_azgaraz",
        display_name = "Karak Azgaraz",
        missions = {
            { key = "dlc_dwarf_interior", name = "Mission of Mercy",       icon = "mines" },
            { key = "dlc_dwarf_exterior", name = "A Grudge Served Cold",   icon = "mountain" },
            { key = "dlc_dwarf_beacons",  name = "Khazukan Kazakit-ha!",   icon = "mountain" },
            { key = "dlc_dwarf_whaling",  name = "A Parting of the Waves", icon = "bay" },
        },
    },
    {
        id = "winds_of_magic",
        display_name = "Winds of Magic",
        missions = {
            { key = "crater", name = "Dark Omens",                         icon = "mountain" },
        },
    },
    {
        id = "drachenfels",
        display_name = "The Curse of Drachenfels",
        missions = {
            { key = "dlc_portals", name = "Old Haunts",                    icon = "temple" },
            { key = "dlc_bastion", name = "Blood in the Darkness",         icon = "tower" },
            { key = "dlc_castle",  name = "The Enchanter's Lair",          icon = "tower" },
        },
    },
    {
        id = "treacherous_adventure",
        display_name = "A Treacherous Adventure",
        missions = {
            { key = "dlc_wizards_trail", name = "Trail of Treachery",      icon = "forest" },
            { key = "dlc_wizards_tower", name = "Tower of Treachery",      icon = "tower" },
        },
    },
    {
        id = "verminous_dreams",
        display_name = "Verminious Dreams",
        missions = {
            { key = "dlc_termite_1", name = "The Forsaken Temple",         icon = "temple" },
            { key = "dlc_termite_2", name = "Devious Delvings",            icon = "mines" },
            { key = "dlc_termite_3", name = "The Well of Dreams",          icon = "gorge" },
        },
    },
    {
        id = "reikland_tales",
        display_name = "Reikland Tales",
        missions = {
            { key = "dlc_reikwald_river", name = "Return to the Reik",     icon = "bay" },
        },
    },
}

-- Annual / holiday / standalone event missions. Listed in a separate "Event Missions"
-- submenu below Campaign Scenarios so they're visually distinct from the regular DLC
-- roster. Fortunes of War is a coliseum survival mission that doesn't fit the campaign
-- progression of any DLC pack — grouped here per user direction.
--
-- `no_books = true` flags missions without tome/grimoire spawners — these can't host
-- Chests of Trials (the tome/grim hook has nothing to convert), so the per-mission
-- toggle gets an explanatory tooltip in VMF settings.
_M.EVENT_MISSIONS = {
    { key = "plaza",               name = "Fortunes of War",                       no_books = true, icon = "temple" },
    { key = "dlc_celebrate_crawl", name = "A Quiet Drink (Anniversary)",           no_books = true, icon = "mines" },
    { key = "dlc_dwarf_fest",      name = "The Feast of Grimnir",                  no_books = true, icon = "mountain" },
}

_M.ADVENTURE_SETTING_PREFIX = "enable_adventure_"

-- Flattened mission catalog: legacy `ADVENTURE_MISSIONS` (with name) and
-- `ADVENTURE_LEVELS` (key-only) preserved for callers in chaos_wastes_tweaker.lua.
-- Includes both DLC campaign missions and annual event missions — every entry in
-- here gets a per-mission toggle and participates in inject_pool().
_M.ADVENTURE_MISSIONS = {}
_M.ADVENTURE_LEVELS = {}
for _, group in ipairs(_M.MISSION_GROUPS) do
    for _, m in ipairs(group.missions) do
        _M.ADVENTURE_MISSIONS[#_M.ADVENTURE_MISSIONS + 1] = m
        _M.ADVENTURE_LEVELS[#_M.ADVENTURE_LEVELS + 1] = m.key
    end
end
for _, m in ipairs(_M.EVENT_MISSIONS) do
    _M.ADVENTURE_MISSIONS[#_M.ADVENTURE_MISSIONS + 1] = m
    _M.ADVENTURE_LEVELS[#_M.ADVENTURE_LEVELS + 1] = m.key
end

-- key → mission entry (with name, icon, etc.). Used to look up icon during inject_pool.
_M.MISSION_BY_KEY = {}
for _, m in ipairs(_M.ADVENTURE_MISSIONS) do
    _M.MISSION_BY_KEY[m.key] = m
end

-- Populated by inject_pool(). Used by chaos_wastes_tweaker.lua to gate the
-- tome/grim → Chest-of-Trials hook on injected-level membership.
_M.IS_INJECTED_ADVENTURE_LEVEL = {}

-- =====================================================================
-- Group-master metadata (#457 "Revamp Mission Availability")
-- =====================================================================
-- Each MISSION_GROUP (DLC / Helmgart campaign) plus the two special groups (the
-- vanilla CW scenarios, and the event missions) gets a MASTER toggle
-- `enable_group_<id>`. A mission counts as enabled iff its group master is ON AND
-- (the group has exactly one mission, OR its per-mission toggle is ON). Groups with
-- a single mission carry no advanced per-mission list (nothing to sub-select), so
-- their master alone decides. Masters default ON, matching the pre-#457 behavior
-- where every mission defaulted enabled under the inject master.
_M.GROUP_MASTER_PREFIX = "enable_group_"
_M.CW_GROUP_ID    = "cw_scenarios"
_M.EVENT_GROUP_ID = "event_missions"

_M.GROUP_ID_BY_KEY = {}   -- adventure/event mission key -> owning group id
_M.GROUP_IS_SINGLE = {}   -- group id -> true when it holds exactly one mission
for _, group in ipairs(_M.MISSION_GROUPS) do
    _M.GROUP_IS_SINGLE[group.id] = (#group.missions == 1)
    for _, m in ipairs(group.missions) do
        _M.GROUP_ID_BY_KEY[m.key] = group.id
    end
end
for _, m in ipairs(_M.EVENT_MISSIONS) do
    _M.GROUP_ID_BY_KEY[m.key] = _M.EVENT_GROUP_ID
end
_M.GROUP_IS_SINGLE[_M.EVENT_GROUP_ID] = (#_M.EVENT_MISSIONS == 1)
_M.GROUP_IS_SINGLE[_M.CW_GROUP_ID]    = (#_M.CW_SCENARIOS == 1)

-- A master defaults ON: mod:get returns the widget default (true) when unset, and an
-- unregistered id reads nil, so `~= false` treats both as enabled.
function _M.group_enabled(group_id)
    if not group_id then return true end
    return mod:get(_M.GROUP_MASTER_PREFIX .. group_id) ~= false
end

-- =====================================================================
-- VMF widget builders (called from _data.lua)
-- =====================================================================

-- One master-toggle widget for a mission group. `missions` is the ordered list;
-- single-mission groups get a bare checkbox (no advanced sub-list). Multi-mission
-- groups nest an "advanced_<id>_group" collapsible holding one checkbox per mission
-- (setting_id `<prefix><key>`). `per_mission_tooltip` (optional) maps a mission entry
-- to a tooltip loc key (used for the event missions' no_books note).
local function build_master_widget(group_id, missions, prefix, per_mission_tooltip)
    local single = (#missions == 1)
    local master = {
        setting_id    = _M.GROUP_MASTER_PREFIX .. group_id,
        type          = "checkbox",
        default_value = true,
        tooltip       = single and "enable_group_single_tooltip" or "enable_group_master_tooltip",
    }
    if not single then
        local sub = {}
        for _, m in ipairs(missions) do
            local w = { setting_id = prefix .. m.key, type = "checkbox", default_value = true }
            if per_mission_tooltip then
                local tt = per_mission_tooltip(m)
                if tt then w.tooltip = tt end
            end
            sub[#sub + 1] = w
        end
        master.sub_widgets = {
            { setting_id = "advanced_" .. group_id .. "_group", type = "group", sub_widgets = sub },
        }
    end
    return master
end

-- The vanilla CW scenarios as one master toggle ("Chaos Wastes Missions") with an
-- advanced per-scenario list. #457.
function _M.build_cw_scenarios_block()
    return build_master_widget(_M.CW_GROUP_ID, _M.CW_SCENARIOS, _M.CW_SETTING_PREFIX, nil)
end

-- Returns a list of master-toggle widgets, one per DLC / campaign. Multi-mission
-- groups expand to an advanced per-mission list; single-mission groups (Winds of
-- Magic, Reikland Tales) are a bare toggle. #457.
function _M.build_campaign_dlc_group_widgets()
    local groups = {}
    for _, group in ipairs(_M.MISSION_GROUPS) do
        groups[#groups + 1] = build_master_widget(group.id, group.missions, _M.ADVENTURE_SETTING_PREFIX, nil)
    end
    return groups
end

-- The event missions as one master toggle ("Event Missions") with an advanced
-- per-mission list. Missions flagged `no_books = true` keep the explanatory tooltip
-- (no tome/grimoire spawners, so no Chests of Trials). #457.
function _M.build_event_missions_block()
    return build_master_widget(_M.EVENT_GROUP_ID, _M.EVENT_MISSIONS, _M.ADVENTURE_SETTING_PREFIX,
        function(m) return m.no_books and "no_book_locations_tooltip" or nil end)
end

-- =====================================================================
-- Localization helpers (called from _localization.lua)
-- =====================================================================

-- Loc entries for every generated widget in the mission-availability tree. Two
-- classes, distinguished by setting_id prefix so the caller's per-map status-tagging
-- loop (localization.lua) can skip the structural ones:
--   * STRUCTURAL (skip per-map tag): `enable_group_<id>` master labels (carry a
--     baked [untested] tag - the #457 revamp is new) and `advanced_<id>_group`
--     collapsible labels ("Choose Missions").
--   * PER-MAP (get the [untested]/[working] tag): `enable_adventure_<key>` /
--     `enable_cw_<key>` individual mission labels.
function _M.build_loc_entries()
    local entries = {}
    -- CW scenarios: master + advanced collapsible + per-scenario labels.
    entries[_M.GROUP_MASTER_PREFIX .. _M.CW_GROUP_ID] = { en = "[untested] Chaos Wastes Missions" }
    entries["advanced_" .. _M.CW_GROUP_ID .. "_group"] = { en = "Choose Missions" }
    for _, scen in ipairs(_M.CW_SCENARIOS) do
        entries[_M.CW_SETTING_PREFIX .. scen.key] = { en = scen.name }
    end
    -- Campaign / DLC groups: one master each; multi-mission groups add an advanced
    -- collapsible + per-mission labels.
    for _, group in ipairs(_M.MISSION_GROUPS) do
        entries[_M.GROUP_MASTER_PREFIX .. group.id] = { en = "[untested] " .. group.display_name }
        if not _M.GROUP_IS_SINGLE[group.id] then
            entries["advanced_" .. group.id .. "_group"] = { en = "Choose Missions" }
        end
        for _, m in ipairs(group.missions) do
            entries[_M.ADVENTURE_SETTING_PREFIX .. m.key] = { en = m.name }
        end
    end
    -- Event missions: master + advanced collapsible + per-mission labels.
    entries[_M.GROUP_MASTER_PREFIX .. _M.EVENT_GROUP_ID] = { en = "[untested] Event Missions" }
    entries["advanced_" .. _M.EVENT_GROUP_ID .. "_group"] = { en = "Choose Missions" }
    for _, m in ipairs(_M.EVENT_MISSIONS) do
        entries[_M.ADVENTURE_SETTING_PREFIX .. m.key] = { en = m.name }
    end
    return entries
end

-- Back-compat alias for the older single-table builder.
_M.build_mission_loc_entries = _M.build_loc_entries

-- =====================================================================
-- Enabled-set queries
-- =====================================================================

function _M.enabled_missions()
    local out = {}
    for _, m in ipairs(_M.ADVENTURE_MISSIONS) do
        local gid = _M.GROUP_ID_BY_KEY[m.key]
        -- #457: gate on the group master, then (for multi-mission groups) the
        -- per-mission toggle. Single-mission groups have no per-mission widget, so
        -- the master alone decides.
        if _M.group_enabled(gid)
                and (_M.GROUP_IS_SINGLE[gid] or mod:get(_M.ADVENTURE_SETTING_PREFIX .. m.key)) then
            out[#out + 1] = m.key
        end
    end
    return out
end

function _M.disabled_cw_scenarios()
    local out = {}
    -- #457: the CW-scenarios master OFF disables every scenario at once (they are
    -- all removed from the pool); otherwise honor the per-scenario toggles.
    local master_on = _M.group_enabled(_M.CW_GROUP_ID)
    for _, scen in ipairs(_M.CW_SCENARIOS) do
        if not master_on or mod:get(_M.CW_SETTING_PREFIX .. scen.key) == false then
            out[#out + 1] = scen.key
        end
    end
    return out
end

-- =====================================================================
-- Per-permutation builders
-- =====================================================================

local ALL_THEMES = { "wastes", "khorne", "nurgle", "slaanesh", "tzeentch", "belakor" }

-- Build pickup_settings for an injected adventure level. Counts mirror what
-- adventure spawners can actually supply:
--   * potions spawners → deus_potions (CW potions)             [eligibility via _can_spawn hook]
--   * painting_scrap spawners → deus_soft_currency (Pilgrim's Coin)
--   * tome/grimoire spawners → deus_cursed_chest (handled by _spawn_guaranteed_pickup hook, NOT counted here)
--   * remaining primary spawners (ammo/healing/grenades/etc.) → deus_weapon_chest (altars)
--     plus the vanilla ammo/healing/grenades that stay in their adventure roles
-- adv = the vanilla adventure level's pickup_settings.default.primary (may be nil).
local function make_cw_pickup_settings(vanilla)
    local adv = vanilla and vanilla.pickup_settings and vanilla.pickup_settings.default
        and vanilla.pickup_settings.default.primary
    local function primary()
        -- Keep adventure's native ammo/grenades/healing/level_events counts;
        -- target CW abundance for deus pickups. Engine logs spawn_debt but
        -- doesn't crash when requested count > available eligible spawners.
        return {
            ammo          = adv and adv.ammo or 5,
            grenades      = adv and adv.grenades or 5,
            healing       = adv and adv.healing or { first_aid_kit = 2, healing_draught = 2 },
            level_events  = adv and adv.level_events or { explosive_barrel = 2, lamp_oil = 2 },
            -- CW pickup counts. The _can_spawn hook below grants eligibility on any
            -- non-tome/grim primary spawner, so deus_potions, deus_soft_currency and
            -- deus_weapon_chest all compete for the SAME finite, shared primary spawner
            -- pool (pickup_system.lua:467-633 iterates pickup_types over one `spawners`
            -- array and permanently table.remove()s each consumed spawner at :621-626).
            -- This is unlike a vanilla CW level, where potion spawners and
            -- painting_scrap→coin spawners are type-partitioned and never contend.
            --
            -- Coin-starvation fix (Abundance-of-Life curse): the curse mutator
            -- (mutator_curse_abundance_of_life.lua:7-11) carries
            -- pickup_system_multipliers = { deus_potions = 3, ... } applied by
            -- MutatorHandler.pickup_settings_updated_settings (mutator_handler.lua:544-560)
            -- BEFORE spawning. It triples deus_potions but leaves deus_soft_currency
            -- untouched (not a key in the curse table), so in the SHARED primary pool
            -- a potions-first allocation pass (pairs() order is non-deterministic in
            -- Lua 5.1) could drain the spawner list and drop coins into silent
            -- spawn_debt (pickup_system.lua:629).
            --
            -- v0.7.165-dev ROBUST fix lives in the `_can_spawn` hook in
            -- chaos_wastes_tweaker_dev.lua (search `_spawner_reserved_for_coins`): a
            -- deterministic ~40% slice of primary spawners is reserved COIN-ONLY by
            -- DENYING deus_potions/deus_weapon_chest eligibility there, so potions can
            -- never claim them regardless of iteration order or the ×3 curse. That
            -- GUARANTEES coins (the prior count-only ratio only reduced the odds).
            --
            -- These counts are now just "how many of each to request"; the guarantee
            -- is the reservation, not the ratio. Request coins generously enough to
            -- fill the reserved slice, and keep potions at a level that feels normal
            -- on NON-cursed injected levels too (×3 curse → 90 requested potions, but
            -- they're confined to the unreserved ~60% of spawners). Only counts change
            -- here — the deus_potions spawn_weighting table is untouched, so the
            -- [0,1) sampler-sum crash class does not apply.
            deus_potions       = 30,
            deus_soft_currency = 30,
            deus_weapon_chest  = 5,  -- altars (1 temper + 1 melee swap + 1 ranged swap + 2 boon)
            -- deus_cursed_chest is handled by the tome/grim spawner hook (book locations).
            -- Setting to 0 here avoids the engine reporting "spawn debt" against a count it
            -- can't satisfy via the regular sampler.
            deus_cursed_chest  = 0,
            -- Disable adventure-only pickup types so the engine doesn't try to spawn them.
            potions        = 0,
            painting_scrap = 0,
        }
    end
    local function secondary()
        -- Secondary draws from a SEPARATE spawner pool (self.secondary_pickup_spawners,
        -- pickup_system.lua:443-449) but the SAME curse multiplier is reapplied to it
        -- (:446). The `_can_spawn` coin reservation (v0.7.165-dev) fires for secondary
        -- spawners too (same hook, same percentage_through_level hash), so coins are
        -- guaranteed here as well -- no need for a coins-heavy ratio as a defense.
        return {
            ammo               = 3,
            grenades           = 4,
            deus_potions       = 10,
            deus_soft_currency = 10,
            healing            = 2,
            potions            = 0,
        }
    end
    return {
        default = { primary = primary(), secondary = secondary() },
        normal  = { primary = primary(), secondary = secondary() },
    }
end

local function make_altar_distribution()
    return {
        [DEUS_CHEST_TYPES.upgrade]     = 1,
        [DEUS_CHEST_TYPES.swap_melee]  = 1,
        [DEUS_CHEST_TYPES.swap_ranged] = 1,
        [DEUS_CHEST_TYPES.power_up]    = 2,
    }
end

-- DLC career packages need to ride along on every injected adventure permutation.
-- When the engine transitions an adventure level into deus mode, the level
-- packages list is what's loaded — and vanilla adventure levels don't include
-- DLC career assets (they're loaded at game start and stay resident on vanilla
-- adventure flow). Our injection apparently triggers an unload-and-reload that
-- drops them, so a bot equipped with a DLC career's weapon (e.g. ghost scythe
-- for Necromancer) hits "Unit not found" on spawn. List every DLC career
-- package here; the engine ignores packages the user doesn't own.
local DLC_CAREER_PACKAGES = {
    "resource_packages/careers/bw_necromancer",   -- shovel DLC
    "resource_packages/careers/we_thornsister",   -- woods DLC
    "resource_packages/careers/dr_engineer",      -- cog DLC
    "resource_packages/careers/es_questingknight", -- lake DLC
    "resource_packages/careers/wh_priest",        -- bless DLC
}

-- (v0.6.6 had a list of base weapon unit packages here that turned out to be
-- treating a symptom — the real fix lives in chaos_wastes_tweaker.lua's
-- `GearUtils.create_equipment` hook, which recovers career_name and pre-resolves
-- per-career `right_hand_unit_override`. See weapon_tweaker CHANGELOG v0.12.23-25
-- for the original investigation. Packages list reverted.)

local function build_permutation_packages(vanilla)
    local out = table.clone(vanilla.packages or {})
    local need = {
        "resource_packages/dlcs/morris_ingame",
        "units/props/inn/deus/deus_chest_01",
        -- Belakor pickup/locus units (blk_locus_01, blk_totem_01, shadow_lieutenant,
        -- belakor_crystal_socket, etc.). Vanilla CW belakor-themed levels load this
        -- via `theme_packages_lookup.belakor` in level_settings_morris.lua. Adventure
        -- bundles don't bring it, so force_belakor's altar spawn fatals on c_api_world.cpp:67
        -- when `World.spawn_unit("units/props/blk/blk_locus_01", ...)` runs and the resource
        -- isn't in the manager. Load on every theme — force_belakor can ignite a Belakor
        -- altar (via _spawn_guaranteed_pickup hook) regardless of which theme rolled.
        "resource_packages/levels/dlcs/morris/belakor_common",
    }
    for _, pkg in ipairs(DLC_CAREER_PACKAGES) do
        need[#need + 1] = pkg
    end
    for _, pkg in ipairs(need) do
        local seen = false
        for _, existing in ipairs(out) do
            if existing == pkg then seen = true; break end
        end
        if not seen then out[#out + 1] = pkg end
    end
    return out
end

-- Register a level key in NetworkLookup.level_keys so the multiplayer level-load RPC
-- can serialize it. NetworkLookup.level_keys is built from LevelSettings at boot
-- (network_lookup.lua:1233) and gets a strict __index metatable (line 2354-2363) that
-- errors on unknown key access. Our post-boot LevelSettings additions are NOT in it
-- — without this registration, _setup_run crashes with "[NetworkLookup.lua] Table
-- level_keys does not contain key: <permutation_key>".
--
-- Use rawget/rawset to bypass the metatable's strict __index.
local function register_network_lookup_key(key)
    if not NetworkLookup or not NetworkLookup.level_keys then return end
    local lookup = NetworkLookup.level_keys
    if rawget(lookup, key) then return end  -- already registered
    local n = #lookup + 1
    rawset(lookup, n, key)
    rawset(lookup, key, n)
end

-- Duplicate pool entries exist only to give the graph solver enough distinct
-- choices.  They must not become distinct network levels.  Vanilla resolves
-- graph-only aliases through config.LEVEL_ALIAS after constructing the themed
-- path key (deus_populate_graph.lua:1096-1099), so point every duplicate
-- permutation back to its already-registered source permutation.
function _M.map_duplicate_level_aliases(config, alias_key, alias_dls)
    if type(config) ~= "table" or type(alias_key) ~= "string"
            or type(alias_dls) ~= "table" or type(alias_dls.base_level_name) ~= "string" then
        return 0
    end
    config.LEVEL_ALIAS = config.LEVEL_ALIAS or {}
    local mapped = 0
    for _, theme_name in ipairs(ALL_THEMES) do
        for _, path in ipairs(alias_dls.paths or { 1 }) do
            local alias_perm = alias_key .. "_" .. theme_name .. "_path" .. path
            local original_perm = alias_dls.base_level_name .. "_" .. theme_name .. "_path" .. path
            config.LEVEL_ALIAS[alias_perm] = original_perm
            mapped = mapped + 1
        end
    end
    return mapped
end

-- =====================================================================
-- Pool mutation
-- =====================================================================

local POOL_SAFETY_THRESHOLD = 4  -- Distinct entries needed per (journey × pool_type)
                                  -- before duplicate-injection kicks in. The only wired
                                  -- solver constraint for TRAVEL/SIGNATURE is
                                  -- prevent_same_level_choice (branch-sibling width;
                                  -- deus_map_populate_settings.lua:222 lists only that
                                  -- validator - prevent_same_level_on_same_path is defined
                                  -- but never wired into a journey). Its provable worst
                                  -- case: a node has <= MAX_INCOMING_CONNECTIONS_PER_NODE
                                  -- (3) parents, each with <= MAX_CONNECTIONS_PER_NODE (2)
                                  -- children, so <= 3 same-type siblings + itself = 4
                                  -- distinct keys (deus_map_base_gen_settings.lua:6-8). 4 is
                                  -- therefore PROVABLY sufficient AND matches the user's
                                  -- "fewer than 4" trigger (issue 487). His alternate
                                  -- "however many non-arena/non-shrine mission nodes the
                                  -- expedition has" framing over-counts: levels MAY repeat
                                  -- across non-sibling nodes down a path (that path-wide
                                  -- validator is unwired), so we need branch width, not
                                  -- total node count. Duplication clones the user's ENABLED
                                  -- missions (never disabled vanilla levels); a zero-enabled
                                  -- pool has nothing to clone and falls back to vanilla.

-- Snapshot of the original (untouched) journey-level LEVEL_AVAILABILITY tables,
-- captured exactly once on first inject. Subsequent calls reset to this snapshot
-- before re-applying filter/inject/duplicates so the operation is idempotent —
-- toggling a CW scenario back ON is undoable, and re-running inject_pool after
-- changing toggles produces the correct end state without leaking removals or
-- accumulating extra entries.
local _snapshot = nil

-- Registry of duplicate aliases already minted this session, keyed by
-- "<journey>\0<pool_type>" -> ordered array of alias keys (array index = dup slot).
-- Lives on the module table (like IS_INJECTED_ADVENTURE_LEVEL) so it survives across
-- the many inject_pool() calls per session (fired on every pool-setting change).
--
-- WHY: reset_to_snapshot() restores LEVEL_AVAILABILITY but NOT the `_dupN` entries
-- added to DEUS_LEVEL_SETTINGS / LevelSettings / NetworkLookup.level_keys. Without
-- reuse, the mint loop's `until not rawget(DEUS_LEVEL_SETTINGS, alias_key)` guard
-- skips every prior `_dupN` and coins a fresh name on each run, so every re-inject
-- grows NetworkLookup.level_keys (a network-synced table we must never SHRINK —
-- removing entries can desync peers) without bound. Reusing the SAME alias per
-- (pool, slot) makes alias creation idempotent and bounds the alias set at
-- POOL_SAFETY_THRESHOLD-1 per pool. Keyed by journey+pool (not base+occurrence) so
-- it's immune to Lua 5.1 pairs() iteration-order changes between runs.
_M._dup_alias_registry = _M._dup_alias_registry or {}

local function take_snapshot()
    if _snapshot then return end
    _snapshot = {}
    if not DEUS_MAP_POPULATE_SETTINGS then return end
    for journey_name, config in pairs(DEUS_MAP_POPULATE_SETTINGS) do
        if config and config.LEVEL_AVAILABILITY then
            _snapshot[journey_name] = {}
            for pool_type, pool in pairs(config.LEVEL_AVAILABILITY) do
                if type(pool) == "table" then
                    local pool_copy = {}
                    for key, entry in pairs(pool) do
                        pool_copy[key] = entry  -- shallow copy: entry is {themes, paths} ref
                    end
                    _snapshot[journey_name][pool_type] = pool_copy
                end
            end
        end
    end
end

local function reset_to_snapshot()
    if not _snapshot then return end
    for journey_name, config in pairs(DEUS_MAP_POPULATE_SETTINGS) do
        local snap = _snapshot[journey_name]
        if snap and config.LEVEL_AVAILABILITY then
            for pool_type, snap_pool in pairs(snap) do
                local cur_pool = config.LEVEL_AVAILABILITY[pool_type]
                if cur_pool then
                    -- Clear current pool
                    for k in pairs(cur_pool) do cur_pool[k] = nil end
                    -- Restore from snapshot
                    for k, v in pairs(snap_pool) do cur_pool[k] = v end
                end
            end
        end
    end
end

-- Remove disabled CW scenarios from every journey's LEVEL_AVAILABILITY[TRAVEL/SIGNATURE].
-- Returns # removed.
local function filter_cw_pool()
    local disabled = _M.disabled_cw_scenarios()
    if #disabled == 0 then return 0 end

    local removed = 0
    for _, config in pairs(DEUS_MAP_POPULATE_SETTINGS) do
        local la = config.LEVEL_AVAILABILITY
        if la then
            for _, pool_type in ipairs({ "TRAVEL", "SIGNATURE" }) do
                local pool = la[pool_type]
                if pool then
                    for _, scen_key in ipairs(disabled) do
                        if pool[scen_key] then
                            pool[scen_key] = nil
                            removed = removed + 1
                        end
                    end
                end
            end
        end
    end
    return removed
end

-- Count the REAL (non-`_dupN`) keys in a pool. Alias keys can't seed the graph on
-- their own (they clone a real key), so the floor is measured against real keys.
local function count_real_keys(pool)
    local n = 0
    for k in pairs(pool) do
        if not (type(k) == "string" and k:find("_dup%d+$")) then n = n + 1 end
    end
    return n
end

-- Underflow-policy classifier (issue 487). PURE - touches no globals, mutates nothing.
-- Given the count of ENABLED (real, non-`_dupN`) missions a TRAVEL/SIGNATURE pool holds
-- after filter+inject, decide how the floor treats it:
--   "ok"        - >= POOL_SAFETY_THRESHOLD distinct missions; the solver is satisfied.
--   "duplicate" - underflow (1 .. threshold-1); clone the ENABLED missions under `_dupN`
--                 aliases so the run REPEATS them. Never backfill disabled vanilla levels.
--   "fallback"  - zero enabled; nothing to clone, so this pool alone falls back to its
--                 vanilla contents (documented via chat notice) rather than freeze.
-- Exposed on the module so /ct_regression_test can assert the contract at runtime
-- without touching live pool state.
function _M.classify_pool_floor(enabled_real_count)
    if not enabled_real_count or enabled_real_count <= 0 then return "fallback" end
    if enabled_real_count < POOL_SAFETY_THRESHOLD then return "duplicate" end
    return "ok"
end

-- Read-only mirror of the local constant, for the regression test.
_M.POOL_SAFETY_THRESHOLD = POOL_SAFETY_THRESHOLD

-- Session guard so the pool-floor chat notice fires ONCE per underflow episode and
-- re-arms when the pool recovers. Keyed by pool type; the value is the last-notified
-- STATE ("fallback" | "repeat" | nil) so a transition between the two states re-fires
-- the right notice. Lives on the module table like the other cross-call state.
_M._floor_notice_shown = _M._floor_notice_shown or {}

-- ZERO-ENABLED FALLBACK (#457 / #487). A configuration that empties a TRAVEL or
-- SIGNATURE pool of ALL enabled missions starves the deus map-graph solver: with no
-- assignable level for that node type it burns its 100000-iteration backtrack budget
-- (deus_populate_graph.lua:1006-1020) = the multi-second load freeze reported in #487.
-- The underflow policy (issue 487) fills a short pool by DUPLICATING the user's ENABLED
-- missions - but a pool with ZERO enabled missions has nothing to clone. Rather than
-- freeze (or silently re-add missions the user disabled), that pool ALONE falls back to
-- its pristine vanilla contents, and the caller posts a chat notice naming the pool.
-- Runs AFTER filter+inject and BEFORE duplication. Returns a { pool_type -> true } map
-- of pools that fell back, for the caller's notice.
local function fall_back_zero_enabled_pools()
    local fellback = {}
    if not DEUS_MAP_POPULATE_SETTINGS then return fellback end
    for journey_name, config in pairs(DEUS_MAP_POPULATE_SETTINGS) do
        local la = config.LEVEL_AVAILABILITY
        if la then
            for _, pool_type in ipairs({ "TRAVEL", "SIGNATURE" }) do
                local pool = la[pool_type]
                if pool and _M.classify_pool_floor(count_real_keys(pool)) == "fallback" then
                    -- Restore this pool's pristine vanilla contents (real keys only).
                    local snap = _snapshot and _snapshot[journey_name] and _snapshot[journey_name][pool_type]
                    if type(snap) == "table" then
                        for k, v in pairs(snap) do
                            if not (type(k) == "string" and k:find("_dup%d+$")) then
                                pool[k] = v
                            end
                        end
                        fellback[pool_type] = true
                    end
                end
            end
        end
    end
    return fellback
end

-- Duplicate any underflow pools by registering `<key>_dupN` aliases that resolve to
-- the same underlying bundle. Each duplicate gets its own LevelSettings permutation
-- entries so `get_level_name(<key_dupN>, theme, 1)` resolves. The duplicates feed the
-- graph generator's pool but render identically to the original.
local function inject_duplicate_aliases()
    local injected = 0
    local dup_pools = {}  -- { pool_type -> true } for pools that underflowed and got dups
    for journey_name, config in pairs(DEUS_MAP_POPULATE_SETTINGS) do
        local la = config.LEVEL_AVAILABILITY
        if la then
            for _, pool_type in ipairs({ "TRAVEL", "SIGNATURE" }) do
                local pool = la[pool_type]
                if pool then
                    -- Snapshot original keys (modifying pool while iterating is unsafe)
                    local keys = {}
                    for k in pairs(pool) do keys[#keys + 1] = k end
                    local n = #keys
                    if _M.classify_pool_floor(n) == "duplicate" then
                        dup_pools[pool_type] = true
                        local deficit = POOL_SAFETY_THRESHOLD - n
                        -- Aliases minted for THIS (journey, pool) on prior runs. We reuse
                        -- them per dup slot instead of minting new "_dupN" names each run
                        -- (see _dup_alias_registry note above) so NetworkLookup.level_keys
                        -- doesn't grow unboundedly across pool-setting changes.
                        local pool_id = tostring(journey_name) .. "\0" .. pool_type
                        local slots = _M._dup_alias_registry[pool_id]
                        if not slots then
                            slots = {}
                            _M._dup_alias_registry[pool_id] = slots
                        end
                        -- Round-robin duplicate-create across existing keys.
                        local dup_idx = 0
                        while deficit > 0 do
                            local alias_key = slots[dup_idx + 1]
                            local alias_dls = alias_key and rawget(DEUS_LEVEL_SETTINGS, alias_key)

                            if not alias_dls then
                                -- No reusable alias for this slot yet (first run, or a larger
                                -- deficit than any previous run) -- mint one and record it in
                                -- the registry so later runs REUSE it (bounded growth).
                                local base_key = keys[(dup_idx % n) + 1]
                                local base_dls = rawget(DEUS_LEVEL_SETTINGS, base_key)
                                if not base_dls then break end
                                local suffix_n = 1
                                repeat
                                    alias_key = base_key .. "_dup" .. suffix_n
                                    suffix_n = suffix_n + 1
                                until not rawget(DEUS_LEVEL_SETTINGS, alias_key) and not pool[alias_key]

                                DEUS_LEVEL_SETTINGS[alias_key] = {
                                    base_level_name = base_dls.base_level_name,
                                    paths           = table.clone(base_dls.paths or { 1 }),
                                    themes          = table.clone(base_dls.themes or { "wastes" }),
                                    pickup_settings = base_dls.pickup_settings,
                                    deus_weapon_chest_distribution = base_dls.deus_weapon_chest_distribution,
                                    display_name    = base_dls.display_name,
                                    locations       = base_dls.locations or {},
                                    packages        = base_dls.packages or {},
                                }
                                slots[dup_idx + 1] = alias_key
                                alias_dls = DEUS_LEVEL_SETTINGS[alias_key]
                            end

                            -- Keep the alias distinct only while vanilla solves the graph.
                            -- The final node.level is rewritten to the source permutation,
                            -- which is already present in LevelSettings/NetworkLookup.  The
                            -- old code registered six network levels per alias; 39 aliases
                            -- plus the 35-mission static catalog produced 1,026 entries and
                            -- exceeded weight_array.max_size=1,024 at network startup (#590).
                            _M.map_duplicate_level_aliases(config, alias_key, alias_dls)

                            -- Add (or re-add, after reset_to_snapshot cleared the pool) the
                            -- alias to this pool. On the reuse path the DEUS_LEVEL_SETTINGS /
                            -- LevelSettings / NetworkLookup entries persist from the first
                            -- mint, so only the pool membership needs restoring.
                            pool[alias_key] = {
                                themes = alias_dls.themes,
                                paths  = alias_dls.paths,
                            }
                            injected = injected + 1
                            deficit = deficit - 1
                            dup_idx = dup_idx + 1
                        end
                    end
                end
            end
        end
    end
    return injected, dup_pools
end

-- Build the LevelSettings / NetworkLookup.level_keys / TerrorEventBlueprints /
-- WeightedRandomTerrorEvents entries for one adventure mission's six theme
-- permutations. Does NOT touch DEUS_MAP_POPULATE_SETTINGS pools — pool selection
-- stays toggle-gated in inject_pool() below. Idempotent: every write is guarded
-- by an existence check.
--
-- Split out of inject_pool() in v0.7.62 so it can run unconditionally regardless
-- of master / per-mission toggles. A client whose toggles are off would otherwise
-- crash at state_loading.lua:449 (`attempt to index local 'level_settings' (a nil
-- value)`) when joining a host who rolled `<adv>_<theme>_path1`. Same bug class
-- as v0.7.60 (dormants) and v0.7.61 (trait boons) — see
-- feedback_vt2_gated_registration_diverges.md.
local function register_mission_resolvables(lvl, mission_entry)
    local vanilla = rawget(LevelSettings, lvl)
    if not vanilla then return false end  -- DLC not owned by this peer

    local icon_id = mission_entry and mission_entry.icon and ("twitch_icon_" .. mission_entry.icon)
        or "twitch_icon_shrine"

    if not rawget(DEUS_LEVEL_SETTINGS, lvl) then
        DEUS_LEVEL_SETTINGS[lvl] = {
            base_level_name = lvl,
            paths = { 1 },
            themes = { "wastes", "khorne", "nurgle", "slaanesh", "tzeentch", "belakor" },
            pickup_settings = make_cw_pickup_settings(vanilla),
            deus_weapon_chest_distribution = make_altar_distribution(),
            display_name = vanilla.display_name,
            locations = vanilla.locations or {},
            packages = {},
            texture_id = icon_id,
        }
    end

    for _, theme_name in ipairs(ALL_THEMES) do
        local permutation_key = lvl .. "_" .. theme_name .. "_path1"
        if not rawget(LevelSettings, permutation_key) then
            local settings_clone = table.clone(vanilla)
            settings_clone.level_name = vanilla.level_name
            settings_clone.level_key = permutation_key
            settings_clone.level_id = permutation_key
            settings_clone.theme = theme_name
            settings_clone.game_mode = "deus"
            settings_clone.mechanism = "deus"
            settings_clone.act = "deus_act"
            settings_clone.act_presentation_order = 1
            settings_clone.act_unlock_order = 0
            settings_clone.dlc_name = "morris"
            settings_clone.disable_percentage_completed = true
            settings_clone.disable_quickplay = true
            settings_clone.ommit_from_lobby_browser = true
            settings_clone.unlockable = true
            settings_clone.display_name = vanilla.display_name
            settings_clone.description_text = vanilla.description_text or vanilla.display_name
            settings_clone.allowed_locked_director_functions = { beastmen = true }
            settings_clone.loading_ui_package_name = vanilla.loading_ui_package_name or "morris/deus_loading_screen_1"
            settings_clone.pickup_settings = make_cw_pickup_settings(vanilla)
            settings_clone.packages = build_permutation_packages(vanilla)
            settings_clone.texture_id = icon_id
            LevelSettings[permutation_key] = settings_clone
        end
        register_network_lookup_key(permutation_key)
        -- TerrorEventBlueprints is built once at boot from LevelSettings; entries
        -- for our post-boot permutation keys are missing. terror_event_mixer.lua:1723
        -- does `TerrorEventBlueprints[level_key][event_name] or GenericTerrorEvents[event_name]`
        -- which crashes on `nil[event_name]` before the OR fallback. Mirror the BASE
        -- adventure level's blueprint table onto each permutation key so the lookup
        -- finds a real table; events not present in the adventure blueprint then fall
        -- through to GenericTerrorEvents (cursed_chest_prototype, etc.).
        if rawget(_G, "TerrorEventBlueprints") and TerrorEventBlueprints[lvl] and not TerrorEventBlueprints[permutation_key] then
            TerrorEventBlueprints[permutation_key] = TerrorEventBlueprints[lvl]
        end
        -- Same problem for WeightedRandomTerrorEvents — terror_event_mixer.lua:1595
        -- does `WeightedRandomTerrorEvents[level_key][event_chunk_name]` and crashes
        -- on `nil[event_chunk_name]` if no entry exists for our permutation key.
        -- Adventure-level flow events (e.g. `nurgle_end_event_loop` on Festering
        -- Ground) hit this when the level loads under a CW permutation.
        -- Mirror the base adventure level's entry onto each permutation key.
        if rawget(_G, "WeightedRandomTerrorEvents") and WeightedRandomTerrorEvents[lvl]
                and not WeightedRandomTerrorEvents[permutation_key] then
            WeightedRandomTerrorEvents[permutation_key] = WeightedRandomTerrorEvents[lvl]
        end
    end
    return true
end

-- Unconditional pre-registration of every adventure mission in the catalog.
-- Runs from inject_pool() before any toggle check (and so before mod-load returns
-- via chaos_wastes_tweaker.lua:54) so two ct peers always have identical
-- LevelSettings/NetworkLookup contents regardless of which adventure toggles each
-- one has set. The crash this prevents: client joins a host running
-- `magnus_belakor_path1`, client has master OR per-mission toggle off → client's
-- LevelSettings lookup returns nil → fatal at state_loading.lua:449. Sorted
-- iteration matches the doctrine for buff/power-up pre-registration in
-- feedback_vt2_gated_registration_diverges.md — same shape of fix.
function _M.pre_register_adventure_lookups()
    if not LevelSettings or not DEUS_LEVEL_SETTINGS or not DEUS_CHEST_TYPES then return end
    local sorted = {}
    for _, m in ipairs(_M.ADVENTURE_MISSIONS) do sorted[#sorted + 1] = m end
    table.sort(sorted, function(a, b) return a.key < b.key end)
    for _, m in ipairs(sorted) do
        register_mission_resolvables(m.key, m)
    end
end

function _M.inject_pool()
    if not LevelSettings or not DEUS_LEVEL_SETTINGS or not DEUS_MAP_POPULATE_SETTINGS or not DEUS_CHEST_TYPES then
        mod:warning("inject_pool: required globals not loaded; skipping")
        return 0
    end

    -- Pre-register every adventure mission's resolvables unconditionally so a peer
    -- whose master / per-mission toggles are off can still resolve a host-advertised
    -- permutation key. Runs before the toggle gate so it covers the master-off case
    -- too. Idempotent — re-running on setting-change is harmless.
    _M.pre_register_adventure_lookups()

    -- First call snapshots vanilla LEVEL_AVAILABILITY; subsequent calls reset to it
    -- so the operation is idempotent (re-running after toggle changes produces the
    -- correct end state without accumulation or missing re-adds).
    take_snapshot()
    reset_to_snapshot()

    -- Master toggle off: leave pool at vanilla snapshot. Per-mission toggles are
    -- ignored entirely so the user can flip the master to deactivate everything
    -- without having to also re-tick every per-mission box.
    if not mod:get("inject_adventure_maps") then
        mod:info("inject_pool: master toggle off; pool reset to vanilla (resolvables pre-registered)")
        return 0
    end

    local enabled = _M.enabled_missions()
    local disabled_cw = _M.disabled_cw_scenarios()

    if #enabled == 0 and #disabled_cw == 0 then
        mod:info("inject_pool: no adventure enabled & no CW disabled; nothing to do (pool reset to vanilla)")
        return 0
    end

    -- 1. Add enabled adventure missions to TRAVEL + SIGNATURE pools.
    -- Per-mission resolvables (DEUS_LEVEL_SETTINGS + per-theme LevelSettings +
    -- NetworkLookup + TerrorEventBlueprints + WeightedRandomTerrorEvents) were
    -- already registered above via pre_register_adventure_lookups(); here we
    -- just flag membership and mutate LEVEL_AVAILABILITY (the toggle-gated bit).
    -- LEVEL_AVAILABILITY entries are RE-ADDED on every call because
    -- reset_to_snapshot above wiped them.
    local injected_adv = 0
    for _, lvl in ipairs(enabled) do
        local dls = rawget(DEUS_LEVEL_SETTINGS, lvl)
        if not dls then
            mod:info("inject_pool: DEUS_LEVEL_SETTINGS.%s missing (DLC not owned?); skipping", lvl)
        else
            _M.IS_INJECTED_ADVENTURE_LEVEL[lvl] = true

            for _, config in pairs(DEUS_MAP_POPULATE_SETTINGS) do
                local la = config.LEVEL_AVAILABILITY
                if la then
                    local entry = {
                        themes = dls.themes,
                        paths  = dls.paths,
                    }
                    if la.TRAVEL    then la.TRAVEL[lvl]    = entry end
                    if la.SIGNATURE then la.SIGNATURE[lvl] = entry end
                end
            end

            injected_adv = injected_adv + 1
        end
    end

    -- 2. Filter out disabled vanilla CW scenarios.
    local removed_cw = filter_cw_pool()

    -- 2b. Zero-enabled fallback (#457/#487): a pool the user emptied of ALL enabled
    -- missions has nothing to duplicate, so it falls back to its vanilla contents (the
    -- notice below names it) rather than starve the graph solver into a load freeze.
    local fellback = fall_back_zero_enabled_pools()

    -- 3. Underflow duplication (#457/#487): a pool with 1..threshold-1 enabled missions
    -- gets its ENABLED missions cloned under `_dupN` aliases, so the run REPEATS them
    -- (we never backfill disabled vanilla levels).
    local dups, dup_pools = inject_duplicate_aliases()

    -- Notice per pool, deduped by state (once per episode; re-armed when the pool
    -- recovers, re-fired if a pool transitions between states). Fallback outranks
    -- repeat - "no enabled missions of this type" is the stronger message.
    for _, pool_type in ipairs({ "TRAVEL", "SIGNATURE" }) do
        local state = fellback[pool_type] and "fallback" or (dup_pools[pool_type] and "repeat" or nil)
        if state then
            if _M._floor_notice_shown[pool_type] ~= state then
                _M._floor_notice_shown[pool_type] = state
                -- Startup chat is version-only (#570). Keep the decision under
                -- the #487 raw-printf prefix so it remains visible with mod
                -- logging OFF and lands beside the freeze breadcrumbs.
                if state == "fallback" then
                    if rawget(_G, "printf") then
                        pcall(printf,
                            "[ct:487] POOL-FLOOR %s had ZERO enabled missions; fell back to vanilla pool contents (nothing to duplicate)",
                            pool_type)
                    end
                else
                    if rawget(_G, "printf") then
                        pcall(printf,
                            "[ct:487] POOL-FLOOR %s underflow; duplicated enabled missions so the run repeats them (no vanilla backfill)",
                            pool_type)
                    end
                end
            end
        else
            _M._floor_notice_shown[pool_type] = nil  -- re-arm once the pool is healthy
        end
    end

    mod:info("Adventure pool: injected %d adventure, removed %d CW, added %d duplicate aliases",
        injected_adv, removed_cw, dups)
    return injected_adv
end

_M.POOL_NOTICE_LOG_ONLY = true

-- =====================================================================
-- Diagnostics
-- =====================================================================

function _M.dump_pool_state()
    mod:echo("=== Pool State ===")
    mod:echo("Master toggle (inject_adventure_maps): " .. tostring(mod:get("inject_adventure_maps")))
    if _snapshot then
        mod:echo("Snapshot present: yes")
    else
        mod:echo("Snapshot present: NO (inject_pool never ran)")
    end
    local enabled = _M.enabled_missions()
    local disabled_cw = _M.disabled_cw_scenarios()
    mod:echo("Adventure missions enabled: " .. #enabled .. " / " .. #_M.ADVENTURE_MISSIONS)
    mod:echo("CW scenarios disabled: " .. #disabled_cw .. " / " .. #_M.CW_SCENARIOS)

    if not DEUS_MAP_POPULATE_SETTINGS then
        mod:echo("(DEUS_MAP_POPULATE_SETTINGS not loaded; check log)")
        return
    end

    mod:info("=== Detailed Pool State ===")
    for journey_name, config in pairs(DEUS_MAP_POPULATE_SETTINGS) do
        local la = config and config.LEVEL_AVAILABILITY
        if la then
            for _, pool_type in ipairs({ "TRAVEL", "SIGNATURE", "SHOP", "ARENA" }) do
                local pool = la[pool_type]
                if pool then
                    local keys = {}
                    for k in pairs(pool) do keys[#keys + 1] = k end
                    table.sort(keys)
                    mod:info("[POOL] %s.%s (%d): %s", journey_name, pool_type, #keys, table.concat(keys, ", "))
                end
            end
        end
    end
    mod:echo("Detailed pool state dumped to log (see %APPDATA%\\Fatshark\\Vermintide 2\\console_logs\\).")
end

return _M
