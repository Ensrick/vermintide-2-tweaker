--[[
_adventure_pool — Chaos Wastes map pool customization.

Two things happen here (gated on inject_adventure_maps master toggle):

  1. Adventure missions are injected into the CW TRAVEL/SIGNATURE pools as
     `<adv_key>_<theme>_path1` permutation entries that point at the adventure
     bundle but flag game_mode/mechanism = "deus".

  2. Vanilla CW scenarios that the user disables are removed from those same
     pools. After filter+injection, if any pool drops below a safety threshold
     we duplicate each remaining level under `_dupN` suffix keys so the graph
     generator's same-level-twice constraints don't deadlock.

ARENA / SHOP / finale arenas / Belakor's Temple / Citadel of Eternity are NEVER
touched — those node types are out of scope.

Catalog format: every entry has `key` (LevelSettings key) and `name` (user-facing
display name shown next to the toggle in VMF settings).
]]

local mod = get_mod("ct")

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
-- then each DLC by release order. DLC group display names are best-guess — user can
-- correct them in chaos_wastes_tweaker_localization.lua's dlc_group_<id> entries.
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
-- VMF widget builders (called from _data.lua)
-- =====================================================================

function _M.build_cw_scenario_widgets()
    local widgets = {}
    for _, scen in ipairs(_M.CW_SCENARIOS) do
        widgets[#widgets + 1] = {
            setting_id    = _M.CW_SETTING_PREFIX .. scen.key,
            type          = "checkbox",
            default_value = true,
        }
    end
    return widgets
end

-- Returns a list of group widgets, one per DLC. Each contains its missions.
function _M.build_campaign_dlc_group_widgets()
    local groups = {}
    for _, group in ipairs(_M.MISSION_GROUPS) do
        local sub = {}
        for _, m in ipairs(group.missions) do
            sub[#sub + 1] = {
                setting_id    = _M.ADVENTURE_SETTING_PREFIX .. m.key,
                type          = "checkbox",
                default_value = true,
            }
        end
        groups[#groups + 1] = {
            setting_id   = "dlc_group_" .. group.id,
            type         = "group",
            sub_widgets  = sub,
        }
    end
    return groups
end

-- Flat list of event-mission toggles for the "Event Missions" subgroup.
-- Tooltips: missions flagged `no_books = true` get a warning that no Chests of
-- Trials can spawn on them (the chest hook converts tome/grimoire spawners, and
-- event missions have neither).
function _M.build_event_mission_widgets()
    local widgets = {}
    for _, m in ipairs(_M.EVENT_MISSIONS) do
        local w = {
            setting_id    = _M.ADVENTURE_SETTING_PREFIX .. m.key,
            type          = "checkbox",
            default_value = true,
        }
        if m.no_books then
            w.tooltip = "no_book_locations_tooltip"
        end
        widgets[#widgets + 1] = w
    end
    return widgets
end

-- =====================================================================
-- Localization helpers (called from _localization.lua)
-- =====================================================================

function _M.build_loc_entries()
    local entries = {}
    -- CW scenarios
    for _, scen in ipairs(_M.CW_SCENARIOS) do
        entries[_M.CW_SETTING_PREFIX .. scen.key] = { en = scen.name }
    end
    -- Campaign DLC missions
    for _, group in ipairs(_M.MISSION_GROUPS) do
        entries["dlc_group_" .. group.id] = { en = group.display_name }
        for _, m in ipairs(group.missions) do
            entries[_M.ADVENTURE_SETTING_PREFIX .. m.key] = { en = m.name }
        end
    end
    -- Event missions (flat list, separate group)
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
        if mod:get(_M.ADVENTURE_SETTING_PREFIX .. m.key) then
            out[#out + 1] = m.key
        end
    end
    return out
end

function _M.disabled_cw_scenarios()
    local out = {}
    for _, scen in ipairs(_M.CW_SCENARIOS) do
        if mod:get(_M.CW_SETTING_PREFIX .. scen.key) == false then
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
            -- Aggressive CW pickup counts (user spec: at least 30 each if they fit).
            -- The _can_spawn hook below grants eligibility on any non-tome/grim primary
            -- spawner, so these compete with ammo/healing/grenades for unclaimed slots.
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

-- =====================================================================
-- Pool mutation
-- =====================================================================

local POOL_SAFETY_THRESHOLD = 4  -- Minimum unique entries needed per (journey × pool_type)
                                  -- before duplicate-injection kicks in. CW graphs can
                                  -- reasonably need 3-4 distinct TRAVEL levels; threshold
                                  -- of 4 gives the constraint validator headroom.

-- Snapshot of the original (untouched) journey-level LEVEL_AVAILABILITY tables,
-- captured exactly once on first inject. Subsequent calls reset to this snapshot
-- before re-applying filter/inject/duplicates so the operation is idempotent —
-- toggling a CW scenario back ON is undoable, and re-running inject_pool after
-- changing toggles produces the correct end state without leaking removals or
-- accumulating extra entries.
local _snapshot = nil

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

-- Duplicate any underflow pools by registering `<key>_dupN` aliases that resolve to
-- the same underlying bundle. Each duplicate gets its own LevelSettings permutation
-- entries so `get_level_name(<key_dupN>, theme, 1)` resolves. The duplicates feed the
-- graph generator's pool but render identically to the original.
local function inject_duplicate_aliases()
    local injected = 0
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
                    if n > 0 and n < POOL_SAFETY_THRESHOLD then
                        local deficit = POOL_SAFETY_THRESHOLD - n
                        -- Round-robin duplicate-create across existing keys.
                        local dup_idx = 0
                        while deficit > 0 do
                            local base_key = keys[(dup_idx % n) + 1]
                            local base_dls = rawget(DEUS_LEVEL_SETTINGS, base_key)
                            if not base_dls then break end
                            local suffix_n = 1
                            local alias_key
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
                            -- Mirror LevelSettings permutation entries so the engine can
                            -- resolve <alias>_<theme>_path<n>.
                            for _, theme_name in ipairs(ALL_THEMES) do
                                for _, path in ipairs(DEUS_LEVEL_SETTINGS[alias_key].paths) do
                                    local original_perm = base_key .. "_" .. theme_name .. "_path" .. path
                                    local alias_perm    = alias_key .. "_" .. theme_name .. "_path" .. path
                                    local source = rawget(LevelSettings, original_perm)
                                    if source and not rawget(LevelSettings, alias_perm) then
                                        local clone = table.clone(source)
                                        clone.level_key = alias_perm
                                        clone.level_id  = alias_perm
                                        LevelSettings[alias_perm] = clone
                                    end
                                    register_network_lookup_key(alias_perm)
                                end
                            end
                            pool[alias_key] = {
                                themes = DEUS_LEVEL_SETTINGS[alias_key].themes,
                                paths  = DEUS_LEVEL_SETTINGS[alias_key].paths,
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
    return injected
end

function _M.inject_pool()
    if not LevelSettings or not DEUS_LEVEL_SETTINGS or not DEUS_MAP_POPULATE_SETTINGS or not DEUS_CHEST_TYPES then
        mod:warning("inject_pool: required globals not loaded; skipping")
        return 0
    end

    -- First call snapshots vanilla LEVEL_AVAILABILITY; subsequent calls reset to it
    -- so the operation is idempotent (re-running after toggle changes produces the
    -- correct end state without accumulation or missing re-adds).
    take_snapshot()
    reset_to_snapshot()

    -- Master toggle off: leave pool at vanilla snapshot. Per-mission toggles are
    -- ignored entirely so the user can flip the master to deactivate everything
    -- without having to also re-tick every per-mission box.
    if not mod:get("inject_adventure_maps") then
        mod:info("inject_pool: master toggle off; pool reset to vanilla")
        return 0
    end

    local enabled = _M.enabled_missions()
    local disabled_cw = _M.disabled_cw_scenarios()

    if #enabled == 0 and #disabled_cw == 0 then
        mod:info("inject_pool: no adventure enabled & no CW disabled; nothing to do (pool reset to vanilla)")
        return 0
    end

    -- 1. Inject adventure missions into TRAVEL + SIGNATURE.
    -- DEUS_LEVEL_SETTINGS + per-theme LevelSettings entries are CREATE-ONCE: once
    -- registered they persist for the session (we cannot un-register Lua entries cleanly,
    -- and re-creating them on every call would churn `level_name`/`packages` references
    -- that other systems may have cached).
    -- LEVEL_AVAILABILITY entries are RE-ADDED on every call because reset_to_snapshot
    -- above wiped them; the snapshot only knows about vanilla CW pools.
    local injected_adv = 0
    for _, lvl in ipairs(enabled) do
        local vanilla = rawget(LevelSettings, lvl)
        if not vanilla then
            mod:info("inject_pool: LevelSettings.%s missing (DLC not owned?); skipping", lvl)
        else
            local mission_entry = _M.MISSION_BY_KEY[lvl]
            local icon_id = mission_entry and mission_entry.icon and ("twitch_icon_" .. mission_entry.icon)
                or "twitch_icon_shrine"  -- defensive fallback if a mission has no icon mapped

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
            _M.IS_INJECTED_ADVENTURE_LEVEL[lvl] = true

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

            for _, config in pairs(DEUS_MAP_POPULATE_SETTINGS) do
                local la = config.LEVEL_AVAILABILITY
                if la then
                    local entry = {
                        themes = DEUS_LEVEL_SETTINGS[lvl].themes,
                        paths  = DEUS_LEVEL_SETTINGS[lvl].paths,
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

    -- 3. Inject duplicate aliases if any pool drops below safety threshold.
    local dups = inject_duplicate_aliases()

    mod:info("Adventure pool: injected %d adventure, removed %d CW, added %d duplicate aliases",
        injected_adv, removed_cw, dups)
    return injected_adv
end

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
