--[[
============================================================================
 wt_dev_anim_picker.lua — Dev: 3P Animation Picker (dynamic catalog)
============================================================================

Live in-game tuning surface for cross-character weapon 3P animations.

DYNAMIC CATALOG (v0.12.98-dev+): instead of a hand-maintained list of ports,
this module derives the catalog at install() time by walking the same
`weapon_unlock_map` table that drives wt's unlock toggles. Every (career,
weapon_key) pair where the source weapon's native owner differs from the
receiver career's character model becomes one row in the picker. WP gets a
distinct top-level submenu (his own skeleton) but bow/crossbow/longbow/
repeating-firearm ports are filtered out for him per
feedback_vt2_no_bows_on_warrior_priest.md. Pairs already managed by CWV
(per `_cwv_managed` in main wt.lua) are skipped to avoid competing surfaces.

Same `M.build_widget_tree() / M.loc_keys() / M.install() / M.on_setting_changed`
signatures as v1 — the lead's wiring in main wt.lua + _data.lua +
_localization.lua expects these exact entry points.

Skeleton-vocab tables are built at install() time from live `Weapons.*`
data — every wield event any natively-owned weapon points at via
`wield_anim_career_3p`/`wield_anim_3p`, plus every `anim_event`/`anim_event_3p`
that appears on the actions of natively-owned weapons. Best-effort
approximation grounded in observable data; picking an event the receiver's
body doesn't author falls through to the previous idle stance (no T-pose,
no crash — see feedback_vt2_no_tpose_default_stance.md), and the user can
dump-and-iterate.

Per VMF_RECIPES § 5: every dropdown gets its OWN options table (no shared
references — silent `<<key>>` cascades if shared).
Per VMF_RECIPES § 6: every `setting_id` is globally unique (`wt_dev_anim_*`).
Per VMF_RECIPES § 9: debug logs gate on `enable_debug_logging`.

NOTE (v0.12.98-dev+): `weapon_unlock_map` and `_cwv_managed` were previously
file-local in wt main and had to be mirrored here verbatim. Main wt.lua now
exposes them as `mod._weapon_unlock_map` and `mod._cwv_managed` so this
module reads the live tables directly — no mirror, no drift. If main wt.lua
ever drops those exposures, install() will warn-and-skip the catalog walk.
============================================================================
--]]

local mod = get_mod("wt")

local M = {}

-- ---------------------------------------------------------------------------
-- Debug helper (mirrors the wt main-file convention — gated on the universal
-- `enable_debug_logging` VMF setting, per VMF_RECIPES § 9).
-- ---------------------------------------------------------------------------

local function _dbg(fmt, ...)
    if mod:get("enable_debug_logging") then
        mod:info("[wt:dev_anim] " .. fmt, ...)
    end
end

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

-- Sentinel value used in dropdown widgets to represent "clear the override".
local UNSET = "__unset__"

-- ---------------------------------------------------------------------------
-- Character key + native-owner inference
-- ---------------------------------------------------------------------------
-- Character key (the top-level submenu bucket) is determined by career prefix
-- with one exception: wh_priest is a distinct skeleton from the other wh_*
-- careers, so he gets his own bucket. Same mapping is used to infer the
-- NATIVE OWNER of a weapon from its key prefix:
--
--   es_* = Kruber (empire-soldier)
--   dr_* = Bardin (dwarf)
--   we_* = Kerillian (wood-elf)
--   wh_* = Saltzpyre (witch-hunter)   -- shared by WP as the prefix family
--   bw_* = Sienna (bright-wizard)
--
-- Owner-vs-receiver: when owner == receiver, the port is native (no remap).
-- When owner != receiver, the port is genuinely cross-character.

local _CHARACTER_ORDER = {
    "kruber", "saltzpyre", "wh_priest", "bardin", "kerillian", "sienna",
}

local _CHARACTER_LABEL = {
    kruber    = "Kruber (Mercenary / Huntsman / Foot Knight / Grail Knight)",
    saltzpyre = "Saltzpyre (WHC / Bounty Hunter / Zealot)",
    wh_priest = "Warrior Priest (distinct skeleton)",
    bardin    = "Bardin (Ranger / Ironbreaker / Slayer / Engineer)",
    kerillian = "Kerillian (Waystalker / Handmaiden / Shade / Sister of the Thorn)",
    sienna    = "Sienna (Battle Wizard / Pyromancer / Unchained / Necromancer)",
}

-- Short labels used in per-port entry titles (the long labels above are
-- only used for the character-submenu headers themselves). Format:
-- "<Source Qualifier> <Weapon Name> rendered on <Short Character Name> body".
local _CHARACTER_SHORT = {
    kruber    = "Kruber",
    saltzpyre = "Saltzpyre",
    wh_priest = "Warrior Priest",
    bardin    = "Bardin",
    kerillian = "Kerillian",
    sienna    = "Sienna",
}

-- ---------------------------------------------------------------------------
-- Weapon display table (v0.12.100-dev+)
-- ---------------------------------------------------------------------------
-- Each cross-character port label combines a SOURCE QUALIFIER (the race /
-- affiliation of the weapon's native owner) with the in-game weapon name.
-- This disambiguates ports where the receiver has a same-name native (e.g.
-- Kruber already has a Greatsword; Kerillian's Greatsword on his body is
-- "Elf Greatsword rendered on Kruber body").
--
-- `_SOURCE_QUALIFIER` is keyed by the 3-char weapon_key prefix; overrides
-- (see `_QUALIFIER_OVERRIDES`) handle special cases (Bretonnian weapons,
-- Warrior-Priest-only `wh_*` entries).
--
-- `_WEAPON_NAME` is the in-game display name. Names match Workshop /
-- in-game tooltip text; keep in sync if a vanilla weapon is renamed.

local _SOURCE_QUALIFIER = {
    es = "Empire",
    dr = "Dwarf",
    we = "Elf",
    wh = "Witch Hunter",
    bw = "Bright Wizard",
}

-- Per-key overrides where the prefix-based qualifier is wrong.
local _QUALIFIER_OVERRIDES = {
    es_sword_shield_breton = "Bretonnian",
    -- Warrior-Priest-only wh_* weapons (these don't appear in cross-character
    -- ports today because WP only cross-receives es_1h_flail, but listed for
    -- future-proofing if WP gets ported elsewhere).
    wh_flail_shield   = "Warrior Priest",
    wh_hammer_book    = "Warrior Priest",
    wh_hammer_shield  = "Warrior Priest",
}

local _WEAPON_NAME = {
    -- Empire (Kruber)
    es_1h_flail               = "Flail",
    es_1h_mace                = "Mace",
    es_1h_sword               = "Sword",
    es_2h_hammer              = "Two-Handed Hammer",
    es_2h_heavy_spear         = "Spear",
    es_2h_sword               = "Greatsword",
    es_2h_sword_executioner   = "Executioner Sword",
    es_bastard_sword          = "Bastard Sword",
    es_blunderbuss            = "Blunderbuss",
    es_deus_01                = "Deus Sword",
    es_dual_wield_hammer_sword = "Hammer & Sword",
    es_halberd                = "Halberd",
    es_handgun                = "Handgun",
    es_longbow                = "Longbow",
    es_mace_shield            = "Mace & Shield",
    es_repeating_handgun      = "Repeater Handgun",
    es_sword_shield           = "Sword & Shield",
    es_sword_shield_breton    = "Sword & Shield",
    -- Dwarf (Bardin)
    dr_1h_axe                 = "Axe",
    dr_1h_hammer              = "Hammer",
    dr_1h_throwing_axes       = "Throwing Axes",
    dr_2h_axe                 = "Greataxe",
    dr_2h_cog_hammer          = "Cog Hammer",
    dr_2h_hammer              = "Two-Handed Hammer",
    dr_2h_pick                = "Pickaxe",
    dr_crossbow               = "Crossbow",
    dr_deus_01                = "Deus Hammer",
    dr_drake_pistol           = "Drakefire Pistols",
    dr_drakegun               = "Drakegun",
    dr_dual_wield_axes        = "Dual Axes",
    dr_dual_wield_hammers     = "Dual Hammers",
    dr_handgun                = "Handgun",
    dr_rakegun                = "Grudge-Raker",
    dr_shield_axe             = "Axe & Shield",
    dr_shield_hammer          = "Hammer & Shield",
    dr_steam_pistol           = "Masterwork Pistol",
    -- Elf (Kerillian)
    we_1h_axe                 = "Axe",
    we_1h_spears_shield       = "Spear & Shield",
    we_1h_sword               = "Sword",
    we_2h_axe                 = "Two-Handed Axe",
    we_2h_sword               = "Greatsword",
    we_crossbow_repeater      = "Repeater Crossbow",
    we_deus_01                = "Moonfire Bow",  -- v0.12.118 mislabel fix (was "Deus Greatsword"; per-char deus_01 keys are CW weapons)
    we_dual_wield_daggers     = "Dual Daggers",
    we_dual_wield_swords      = "Dual Swords",
    we_dual_wield_sword_dagger = "Sword & Dagger",
    we_javelin                = "Javelin",
    we_life_staff             = "Deepwood Staff",  -- v0.12.118 mislabel fix (was "Moonfire Bow")
    we_longbow                = "Longbow",
    we_shortbow               = "Shortbow",
    we_shortbow_hagbane       = "Hagbane Shortbow",
    we_spear                  = "Spear",
    -- Witch Hunter (Saltzpyre) and Warrior Priest
    wh_1h_axe                 = "Axe",
    wh_1h_falchion            = "Falchion",
    wh_1h_hammer              = "Hammer",
    wh_2h_billhook            = "Billhook",
    wh_2h_hammer              = "Two-Handed Hammer",
    wh_2h_sword               = "Two-Handed Sword",
    wh_brace_of_pistols       = "Brace of Pistols",
    wh_crossbow               = "Crossbow",
    wh_crossbow_repeater      = "Repeater Crossbow",
    wh_deus_01                = "Deus Rapier",
    wh_dual_hammer            = "Dual Hammers",
    wh_dual_wield_axe_falchion = "Axe & Falchion",
    wh_fencing_sword          = "Rapier",
    wh_flail_shield           = "Flail & Shield",
    wh_hammer_book            = "Hammer & Book",
    wh_hammer_shield          = "Hammer & Shield",
    wh_repeating_pistols      = "Repeater Pistol",
    -- Bright Wizard (Sienna)
    bw_1h_crowbill            = "Crowbill",
    bw_1h_flail_flaming       = "Flaming Flail",
    bw_1h_mace                = "Mace",
    bw_dagger                 = "Dagger",
    bw_deus_01                = "Deus Staff",
    bw_flame_sword            = "Flaming Sword",
    bw_ghost_scythe           = "Ghost Scythe",
    bw_necromancy_staff       = "Soulstealer Staff",
    bw_skullstaff_beam        = "Beam Staff",
    bw_skullstaff_fireball    = "Fireball Staff",
    bw_skullstaff_flamethrower = "Flamethrower Staff",
    bw_skullstaff_geiser      = "Geyser Staff",
    bw_skullstaff_spear       = "Bolt Staff",
    bw_sword                  = "Sword",
}

local function _source_qualifier(weapon_key)
    if _QUALIFIER_OVERRIDES[weapon_key] then return _QUALIFIER_OVERRIDES[weapon_key] end
    local pfx = weapon_key and weapon_key:sub(1, 2)
    return _SOURCE_QUALIFIER[pfx] or "?"
end

-- ---------------------------------------------------------------------------
-- Target-weapon resolution (v0.12.101-dev+)
-- ---------------------------------------------------------------------------
-- The existing patcher block in main wt.lua (`_WIELD_ANIM_CAREER_3P_PATCHES`
-- at weapon_tweaker.lua:2300, plus the per-template `_patch_*` functions
-- nearby) sets `wield_anim_career_3p[<receiver_career>]` to a `to_<stance>`
-- event for every cross-character port whose target weapon is already
-- decided. We derive the TARGET TEMPLATE from that event — no separate
-- target map to maintain.
--
-- When a port's first-career wield event is in this table, the picker:
--   * Drops the wield dropdown (decision is encoded, not negotiable).
--   * Builds per-attack `anim_event_3p` dropdowns filtered to the target
--     template's `actions[*][*].anim_event` vocab — every animation that
--     target weapon authors, nothing else.
--   * Annotates the port label with "(using <Target Name> animations)".

local _WIELD_EVENT_TO_TARGET = {
    -- wield_event = { template = "<canonical>", display = "<in-game name>" }
    to_polearm           = { template = "two_handed_halberds_template_1", display = "Empire Halberd" },
    to_2h_billhook       = { template = "two_handed_billhooks_template",  display = "Witch Hunter Billhook" },
    to_crossbow          = { template = "crossbow_template_1",            display = "Witch Hunter Crossbow" },
    to_repeating_handgun = { template = "repeating_handgun_template_1",   display = "Empire Repeater Handgun" },
    to_handgun           = { template = "handgun_template_1",             display = "Empire Handgun" },
    to_brace_of_pistols  = { template = "brace_of_pistols_template_1",    display = "Witch Hunter Brace of Pistols" },
    -- Add more as decisions get encoded in _WIELD_ANIM_CAREER_3P_PATCHES.
}

local function _resolve_target_for_port(entry)
    local tpl = Weapons and rawget(Weapons, entry.template_name)
    if not tpl or not tpl.wield_anim_career_3p then return nil end
    local first_career = entry.careers and entry.careers[1]
    if not first_career then return nil end
    local wield = tpl.wield_anim_career_3p[first_career]
    if not wield then return nil end
    return _WIELD_EVENT_TO_TARGET[wield]
end

local function _collect_target_anim_event_vocab(target_template_name)
    local tpl = Weapons and rawget(Weapons, target_template_name)
    if not tpl or not tpl.actions then return {} end
    local set, out = {}, {}
    for _, action_group in pairs(tpl.actions) do
        if type(action_group) == "table" then
            for _, sub in pairs(action_group) do
                if type(sub) == "table" then
                    -- Read both fields: vanilla uses `anim_event` for both
                    -- 1p and 3p (3p is implicit). Some templates also set
                    -- `anim_event_3p` for an explicit override.
                    local e1 = sub.anim_event
                    local e2 = sub.anim_event_3p
                    if type(e1) == "string" and not set[e1] then set[e1] = true; out[#out + 1] = e1 end
                    if type(e2) == "string" and not set[e2] then set[e2] = true; out[#out + 1] = e2 end
                end
            end
        end
    end
    table.sort(out)
    return out
end

-- Receiver character bucket from a career name.
local function _char_key_for_career(career)
    if not career then return nil end
    if career == "wh_priest" then return "wh_priest" end
    local prefix2 = career:sub(1, 3)
    if prefix2 == "es_" then return "kruber"
    elseif prefix2 == "dr_" then return "bardin"
    elseif prefix2 == "we_" then return "kerillian"
    elseif prefix2 == "wh_" then return "saltzpyre"
    elseif prefix2 == "bw_" then return "sienna"
    end
    return nil
end

-- Native owner character (one of the six top-level keys) from a weapon_key.
-- Returns nil for unrecognized prefixes (defensive — weapon_unlock_map only
-- holds known prefixes today, but it's cheap to guard).
local function _native_owner_for_weapon_key(weapon_key)
    if not weapon_key then return nil end
    local prefix2 = weapon_key:sub(1, 3)
    if prefix2 == "es_" then return "kruber"
    elseif prefix2 == "dr_" then return "bardin"
    elseif prefix2 == "we_" then return "kerillian"
    elseif prefix2 == "wh_" then
        -- Native owner of the wh_* prefix family is Saltzpyre. Warrior Priest
        -- shares the prefix but is a distinct skeleton — handled as a
        -- RECEIVER, not as an owner.
        return "saltzpyre"
    elseif prefix2 == "bw_" then return "sienna"
    end
    return nil
end

-- Whether a weapon_key looks like a ranged firearm/bow that WP's skeleton
-- doesn't author (no `to_longbow` / `to_crossbow` / `to_repeating_*` /
-- `to_handgun` / `to_brace_of_pistols` / `to_blunderbuss` wields on the
-- priest body). Used to filter the catalog walk so WP never gets a bow row.
local _WP_FORBIDDEN_SUBSTRINGS = {
    "longbow", "crossbow", "shortbow", "bow", -- bow family
    "handgun", "repeating", "blunderbuss",    -- firearm family
    "pistol", "brace_of_pistols",             -- pistol family
    "drake",                                  -- drake* firearms (Bardin)
    "javelin", "throwing_axes",               -- thrown ranged
}
local function _wp_forbidden_weapon(weapon_key)
    if not weapon_key then return false end
    for _, sub in ipairs(_WP_FORBIDDEN_SUBSTRINGS) do
        if weapon_key:find(sub, 1, true) then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Source-of-truth (v0.12.99-dev+)
-- ---------------------------------------------------------------------------
-- v0.12.98-dev attempted to read from `mod._weapon_unlock_map`, which was
-- nil at _data.lua time — VMF calls _data.lua before main wt.lua finishes,
-- so the exposure hadn't happened yet. Picker built an empty catalog → 0
-- sub_widgets → VMF rejected the top-level group → wt failed to load.
-- v0.12.99-dev fix: `mod:dofile` `wt_unlock_data` directly. Same file main
-- wt.lua loads. No load-order dependency, no mirror to drift.

local _UNLOCK_DATA = mod:dofile("scripts/mods/weapon_tweaker/wt_unlock_data")

local function _get_unlock_map()
    return _UNLOCK_DATA.weapon_unlock_map
end

local function _get_cwv_managed()
    return _UNLOCK_DATA.cwv_managed
end

-- ---------------------------------------------------------------------------
-- Linear-scan helper. Lua 5.1 has no built-in `table.contains`. Declared
-- BEFORE first call site per feedback_lua_forward_reference.md.
-- ---------------------------------------------------------------------------
local function _is_in(t, v)
    for i = 1, #t do
        if t[i] == v then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Weapon label builder (v0.12.100-dev+)
-- ---------------------------------------------------------------------------
-- Returns "<Source Qualifier> <Weapon Name>" — the source-character-qualified
-- name used in port labels. Disambiguates same-named weapons across
-- characters (e.g. Kerillian's Greatsword vs Kruber's: "Elf Greatsword" vs
-- "Empire Greatsword"). Falls back to a humanized weapon_key if the curated
-- table is missing the entry (flagged at install time via _OPEN_QUESTIONS).

local function _humanize_weapon_key_fallback(weapon_key)
    if not weapon_key then return "?" end
    local stripped = weapon_key:gsub("^[a-z][a-z]_", "")
    stripped = stripped:gsub("_", " ")
    stripped = stripped:gsub("(%a)(%w*)", function(first, rest) return first:upper() .. rest end)
    return stripped
end

local function _weapon_display_name(weapon_key)
    if not weapon_key then return "?" end
    local qualifier = _source_qualifier(weapon_key)
    local name = _WEAPON_NAME[weapon_key] or _humanize_weapon_key_fallback(weapon_key)
    return qualifier .. " " .. name
end

-- ---------------------------------------------------------------------------
-- Skeleton vocabulary builders (live, install-time)
-- ---------------------------------------------------------------------------
-- For each character model, enumerate the wield events + anim_event vocab
-- the natively-owned weapons author. Result: per-character_key vocab tables
-- used by the dropdown option builders.
--
-- Wield vocab per character model:
--   • Every Weapons.<tpl>.wield_anim_career_3p[<career>] where <career>
--     belongs to that character model AND the weapon is natively owned by
--     that character.
--   • Plus Weapons.<tpl>.wield_anim_3p for every natively-owned weapon.
--   • Plus Weapons.<tpl>.wield_anim (1P-side, but on many templates this is
--     the same as wield_anim_3p and is the only field present).
--
-- Anim-event vocab per character model:
--   • Every distinct `actions[*][*].anim_event` across natively-owned
--     templates.
--   • Plus every distinct `actions[*][*].anim_event_3p` across those same
--     templates (existing per-action 3P overrides — the patcher-applied
--     ones AND any vanilla ones).
--
-- "Natively owned" means the weapon_key's prefix matches the character key
-- (per `_native_owner_for_weapon_key`).
--
-- Both vocabs are best-effort approximations. If the user picks a value the
-- receiver's body doesn't author the 3P playback falls through to the
-- previous-weapon idle stance (no T-pose, no crash). The user dumps via
-- `/wt_dump_anim_picks` and the lead folds confirmed-working values back
-- into the static patcher tables.

local _live_wield_vocab = {}      -- char_key -> sorted unique list
local _live_anim_event_vocab = {} -- char_key -> sorted unique list

-- Returns true if a weapon_key is natively owned by this character model.
-- `kerillian` matches `we_*`, `bardin` matches `dr_*`, etc.
local _NATIVE_PREFIX_BY_CHAR = {
    kruber    = "es_",
    bardin    = "dr_",
    kerillian = "we_",
    saltzpyre = "wh_",
    -- wh_priest shares the `wh_` prefix family with Saltzpyre. For VOCAB
    -- BUILDING this is over-permissive — WP's skeleton authors fewer events
    -- than the WHC/BH/Zealot skeleton (no `to_brace_of_pistols`,
    -- `to_crossbow`, `to_repeating_pistol`, etc.). Since WP's port list is
    -- already filtered by `_wp_forbidden_weapon` to exclude bow/crossbow/
    -- firearm receivers entirely, the over-permissive vocab only shows up
    -- as extra dropdown options on the few melee rows that DO land on WP
    -- (currently just `es_1h_flail`). Best-effort approximation per the
    -- spec; the user picks, tries in-game, dumps what works.
    wh_priest = "wh_",
    sienna    = "bw_",
}

local function _weapon_native_to_char(weapon_key, char_key)
    if not weapon_key or not char_key then return false end
    local prefix = _NATIVE_PREFIX_BY_CHAR[char_key]
    if not prefix then return false end
    return weapon_key:sub(1, #prefix) == prefix
end

-- Lookup of every template name natively owned by a character. Built by
-- iterating ItemMasterList once.
local function _build_native_templates_by_char()
    local out = {}
    for _, char_key in ipairs(_CHARACTER_ORDER) do out[char_key] = {} end
    if not ItemMasterList then return out end
    -- Walk via pairs() — ItemMasterList is metatable-protected on strict
    -- builds; rawget is the cited convention but we want EVERY entry, so
    -- iterate the raw pairs and tolerate any single-entry pcall failure.
    for weapon_key, item in pairs(ItemMasterList) do
        if type(item) == "table" and type(weapon_key) == "string" then
            local tpl = item.template
            if type(tpl) == "string" then
                for _, char_key in ipairs(_CHARACTER_ORDER) do
                    if _weapon_native_to_char(weapon_key, char_key) then
                        out[char_key][tpl] = true
                    end
                end
            end
        end
    end
    return out
end

-- Iterate all templates natively owned by a character, calling fn(template_name, tpl_table).
local function _foreach_native_template(char_key, native_templates, fn)
    local templates = native_templates[char_key]
    if not templates or not Weapons then return end
    for tpl_name in pairs(templates) do
        local tpl = rawget(Weapons, tpl_name) -- rawget per repo convention
        if tpl then fn(tpl_name, tpl) end
    end
end

-- Returns sorted-unique list out of an arbitrary-keyed set.
local function _sorted_unique_keys(set)
    local out = {}
    for k in pairs(set) do out[#out + 1] = k end
    table.sort(out)
    return out
end

-- Build the per-character live wield vocab.
local function _build_live_wield_vocab(native_templates)
    local result = {}
    for _, char_key in ipairs(_CHARACTER_ORDER) do
        local set = {}
        _foreach_native_template(char_key, native_templates, function(_, tpl)
            -- 3P wield default(s)
            if type(tpl.wield_anim_3p) == "string" then set[tpl.wield_anim_3p] = true end
            if type(tpl.wield_anim)    == "string" then set[tpl.wield_anim]    = true end
            -- Per-career 3P wield overrides.
            local map = tpl.wield_anim_career_3p
            if type(map) == "table" then
                for career, ev in pairs(map) do
                    -- Only keep events whose career belongs to THIS character
                    -- bucket — `to_2h_billhook` on `wh_captain` belongs in
                    -- Saltzpyre's vocab, not Kerillian's, even though the
                    -- template might be elf-native.
                    if _char_key_for_career(career) == char_key and type(ev) == "string" then
                        set[ev] = true
                    end
                end
            end
        end)
        result[char_key] = _sorted_unique_keys(set)
    end
    return result
end

-- Build the per-character live anim_event vocab.
local function _build_live_anim_event_vocab(native_templates)
    local result = {}
    for _, char_key in ipairs(_CHARACTER_ORDER) do
        local set = {}
        _foreach_native_template(char_key, native_templates, function(_, tpl)
            if type(tpl.actions) == "table" then
                for _, action_group in pairs(tpl.actions) do
                    if type(action_group) == "table" then
                        for _, sub in pairs(action_group) do
                            if type(sub) == "table" then
                                if type(sub.anim_event)    == "string" then set[sub.anim_event]    = true end
                                if type(sub.anim_event_3p) == "string" then set[sub.anim_event_3p] = true end
                            end
                        end
                    end
                end
            end
        end)
        result[char_key] = _sorted_unique_keys(set)
    end
    return result
end

-- ---------------------------------------------------------------------------
-- Dropdown options factories (per VMF_RECIPES § 5 — fresh table per widget)
-- ---------------------------------------------------------------------------

local function _build_wield_options(char_key, current_value)
    local vocab = _live_wield_vocab[char_key] or {}
    local opts = {}
    local seen = {}

    if current_value and current_value ~= UNSET and not _is_in(vocab, current_value) then
        opts[#opts + 1] = { text = current_value .. " (current)", value = current_value }
        seen[current_value] = true
    end

    for _, v in ipairs(vocab) do
        if not seen[v] then
            opts[#opts + 1] = { text = v, value = v }
            seen[v] = true
        end
    end

    opts[#opts + 1] = { text = "(unset — fall through)", value = UNSET }
    return opts
end

local function _build_anim_event_options(char_key, source_event, current_value)
    local vocab = _live_anim_event_vocab[char_key] or {}
    local opts = {}
    local seen = {}

    if current_value and current_value ~= UNSET and not _is_in(vocab, current_value) then
        opts[#opts + 1] = { text = current_value .. " (current)", value = current_value }
        seen[current_value] = true
    end

    if source_event and not seen[source_event] then
        opts[#opts + 1] = { text = source_event .. " (source — passthrough)", value = source_event }
        seen[source_event] = true
    end

    for _, v in ipairs(vocab) do
        if not seen[v] then
            opts[#opts + 1] = { text = v, value = v }
            seen[v] = true
        end
    end

    opts[#opts + 1] = { text = "(unset — fall through)", value = UNSET }
    return opts
end

-- ---------------------------------------------------------------------------
-- Template / action-event introspection
-- ---------------------------------------------------------------------------

local function _collect_source_anim_events(template_name)
    local tpl = Weapons and rawget(Weapons, template_name)
    if not tpl or not tpl.actions then return nil end
    local seen, out = {}, {}
    for _, action_group in pairs(tpl.actions) do
        if type(action_group) == "table" then
            for _, sub in pairs(action_group) do
                if type(sub) == "table" and type(sub.anim_event) == "string" and not seen[sub.anim_event] then
                    seen[sub.anim_event] = true
                    out[#out + 1] = sub.anim_event
                end
            end
        end
    end
    table.sort(out)
    return out
end

local function _first_anim_event_3p_for(template_name, source_event)
    local tpl = Weapons and rawget(Weapons, template_name)
    if not tpl or not tpl.actions then return nil end
    for _, action_group in pairs(tpl.actions) do
        if type(action_group) == "table" then
            for _, sub in pairs(action_group) do
                if type(sub) == "table" and sub.anim_event == source_event then
                    return sub.anim_event_3p
                end
            end
        end
    end
    return nil
end

-- Resolve weapon_key → template_name via ItemMasterList. rawget per repo
-- convention (DEVELOPMENT.md "rawget for fragile globals"). Returns nil on
-- any failure to resolve.
local function _resolve_template(weapon_key)
    if not ItemMasterList or not weapon_key then return nil end
    local item = rawget(ItemMasterList, weapon_key)
    if not item then return nil end
    return item.template
end

-- ---------------------------------------------------------------------------
-- Dynamic catalog construction
-- ---------------------------------------------------------------------------
-- Walks `_unlock_map`, filters per the conversion rules:
--   1. owner != receiver (skip natives)
--   2. WP + bow/crossbow/firearm = skip
--   3. _cwv_managed[career][weapon_key] = skip
--   4. unresolved template = warn + skip
-- Coalesces receiver careers sharing the same template within a character
-- bucket into one port entry. Returns a list of entries:
--   { port_id, char_key, template_name, weapon_key, label, careers={...} }

local _OPEN_QUESTIONS = {} -- collects warnings for status report (unresolved templates, etc.)

-- Forward-declared locals (assigned further down). Declared here so
-- `_build_dynamic_catalog` can reference `_stable_keys_of`, and
-- `M.build_widget_tree` can reference `_ensure_catalog_built`, without
-- relying on global-namespace fallback. See feedback_lua_forward_reference.md.
local _stable_keys_of
local _ensure_catalog_built

local function _build_dynamic_catalog()
    -- Read live tables off main wt.lua. If main hasn't exposed them (e.g.
    -- this module loaded but main wt.lua errored out before reaching the
    -- exposure block), warn and return an empty catalog — picker will
    -- surface zero entries rather than crash.
    local _unlock_map   = _get_unlock_map()
    local _cwv_managed  = _get_cwv_managed()
    if not _unlock_map then
        mod:warning("[wt:dev_anim] mod._weapon_unlock_map is nil — main wt.lua didn't expose it. Picker will be empty until main wt.lua initializes.")
        return {}, {}
    end
    _cwv_managed = _cwv_managed or {} -- harmless if main didn't expose; no pairs get CWV-skipped.

    -- (receiver_char_key, template_name) -> entry
    local index = {}
    -- Stable list of insertion order so menu order is deterministic.
    local order = {}

    for _, career in _stable_keys_of(_unlock_map) do
        local weapon_keys = _unlock_map[career]
        local receiver_char = _char_key_for_career(career)
        if not receiver_char then
            _OPEN_QUESTIONS[#_OPEN_QUESTIONS + 1] = "unknown char for career " .. tostring(career)
        else
            for _, weapon_key in ipairs(weapon_keys) do
                local owner = _native_owner_for_weapon_key(weapon_key)

                -- Filter (1): native — skip. Per the spec, `wh_*` weapons
                -- are native to BOTH Saltzpyre and Warrior Priest (they
                -- share the `wh_` prefix family). So for receiver=wh_priest,
                -- owner=saltzpyre (i.e. any wh_-prefixed weapon) counts as
                -- native and gets skipped. Result: WP's submenu lists only
                -- the genuinely cross-prefix entries in his row (currently
                -- just `es_1h_flail`).
                local is_native = (owner == receiver_char)
                if receiver_char == "wh_priest" and owner == "saltzpyre" then
                    is_native = true
                end

                -- Filter (2): WP + ranged weapon — skip.
                local wp_forbidden = (receiver_char == "wh_priest" and _wp_forbidden_weapon(weapon_key))

                -- Filter (3): CWV-managed pair — skip.
                local cwv_owned = (_cwv_managed[career] and _cwv_managed[career][weapon_key]) or false

                if not is_native and not wp_forbidden and not cwv_owned then
                    -- Filter (4): resolve template.
                    local template_name = _resolve_template(weapon_key)
                    if not template_name then
                        local msg = "ItemMasterList["..weapon_key.."] missing or has no .template field"
                        _OPEN_QUESTIONS[#_OPEN_QUESTIONS + 1] = msg
                        mod:warning("[wt:dev_anim] %s — skipping", msg)
                    else
                        local idx_key = receiver_char .. "|" .. template_name
                        local entry = index[idx_key]
                        if not entry then
                            entry = {
                                char_key      = receiver_char,
                                template_name = template_name,
                                weapon_key    = weapon_key,
                                careers       = {},
                                _careers_seen = {},
                            }
                            entry.port_id = "p_" .. receiver_char .. "_" .. weapon_key
                                              .. "_" .. template_name
                            -- Label resolved below once careers are populated
                            -- (we need careers[1] to resolve the target weapon).
                            entry.label = nil
                            index[idx_key] = entry
                            order[#order + 1] = idx_key
                        end
                        if not entry._careers_seen[career] then
                            entry._careers_seen[career] = true
                            entry.careers[#entry.careers + 1] = career
                        end
                    end
                end
            end
        end
    end

    -- Materialize in insertion order; sort careers within each entry for
    -- predictable display. Resolve target weapon NOW so labels and loc keys
    -- have access to the annotation.
    local out = {}
    for _, idx_key in ipairs(order) do
        local entry = index[idx_key]
        table.sort(entry.careers)
        entry._careers_seen = nil
        local target = _resolve_target_for_port(entry)
        if target then
            entry.target_template = target.template
            entry.target_display  = target.display
            entry.label = string.format(
                "%s rendered on %s body  ·  using %s animations",
                _weapon_display_name(entry.weapon_key),
                _CHARACTER_SHORT[entry.char_key] or entry.char_key,
                target.display
            )
        else
            entry.label = string.format(
                "%s rendered on %s body",
                _weapon_display_name(entry.weapon_key),
                _CHARACTER_SHORT[entry.char_key] or entry.char_key
            )
        end
        out[#out + 1] = entry
    end
    return out
end

-- Sorted-iteration helper for the unlock_map walk so career order is
-- deterministic across runs. Returns an iterator suitable for use in
-- `for i, k in _stable_keys_of(t) do`.
function _stable_keys_of(t) -- assigned to the forward local declared above

    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    local i = 0
    return function()
        i = i + 1
        local k = keys[i]
        if k == nil then return nil end
        return i, k
    end
end

-- The live catalog. Populated by `_install_catalog()` at install-time after
-- `Weapons` and `ItemMasterList` are guaranteed present.
local _CATALOG = {}

-- ---------------------------------------------------------------------------
-- setting_id factories (globally unique per VMF_RECIPES § 6)
-- ---------------------------------------------------------------------------

-- v0.12.100-dev: one wield dropdown per port (not per career). All careers
-- on the same character model share the same skeleton/animation, so they
-- should always have the same wield event. Apply writes to every career in
-- `entry.careers`.
local function _sid_wield(port_id)
    return "wt_dev_anim_" .. port_id .. "_w"
end

local function _sid_anim_event(port_id, source_event)
    return "wt_dev_anim_" .. port_id .. "_ev_" .. source_event
end

local function _sid_group(port_id)
    return "wt_dev_anim_grp_" .. port_id
end

local function _sid_char_group(char_key)
    return "wt_dev_anim_char_" .. char_key
end

-- setting_id -> { port_id, template_name, kind, career|source_event, ... }
local _setting_index = {}

-- ---------------------------------------------------------------------------
-- Widget tree construction
-- ---------------------------------------------------------------------------

-- v0.12.101-dev: per-port option builder. If the port has a decided target
-- weapon (derived from wield_anim_career_3p — see _resolve_target_for_port),
-- use target's anim_event vocab for ALL per-attack dropdowns and DROP the
-- wield dropdown. Otherwise fall back to receiver-character broad vocab.
local function _build_port_group(entry)
    local sub_widgets = {}
    local tpl = Weapons and rawget(Weapons, entry.template_name)
    local tpl_present = tpl ~= nil

    -- Target weapon already resolved at catalog build time (entry.target_template).
    local target_vocab
    if entry.target_template then
        target_vocab = _collect_target_anim_event_vocab(entry.target_template)
    end

    -- Wield row: ONLY surfaced when no target weapon is decided. With a
    -- target, the wield event is fixed by the patcher in main wt.lua and a
    -- dropdown would just confuse the user. v0.12.101-dev.
    if not entry.target_template then
        local sid = _sid_wield(entry.port_id)
        local cur
        if tpl_present and tpl.wield_anim_career_3p and entry.careers[1] then
            cur = tpl.wield_anim_career_3p[entry.careers[1]]
        end
        local default_value = cur or UNSET

        sub_widgets[#sub_widgets + 1] = {
            setting_id    = sid,
            type          = "dropdown",
            default_value = default_value,
            options       = _build_wield_options(entry.char_key, default_value),
        }
        _setting_index[sid] = {
            port_id       = entry.port_id,
            template_name = entry.template_name,
            kind          = "wield",
            careers       = entry.careers,
            receiver_char = entry.char_key,
            -- v0.12.118: captured so reapply_stored_picks can tell user-changed
            -- settings (stored value ~= build-time default) from untouched ones.
            default_value = default_value,
        }
    end

    -- anim_event rows — one per unique source anim_event in the source
    -- template. Dropdown options:
    --   * With a target weapon: every anim_event the TARGET template
    --     authors (filtered, focused). The user picks which target anim
    --     plays for each source attack.
    --   * Without a target: broad receiver-character vocab (legacy
    --     behavior, useful for ports the user hasn't decided on yet).
    local source_events = _collect_source_anim_events(entry.template_name)
    if source_events then
        for _, source_event in ipairs(source_events) do
            local sid = _sid_anim_event(entry.port_id, source_event)
            local cur = _first_anim_event_3p_for(entry.template_name, source_event)
            local default_value = cur or UNSET

            local options
            if target_vocab then
                -- Filtered to target weapon's vocab. Plus an UNSET sentinel.
                options = {}
                local seen = {}
                if default_value ~= UNSET and not _is_in(target_vocab, default_value) then
                    options[#options + 1] = { text = default_value .. " (current)", value = default_value }
                    seen[default_value] = true
                end
                for _, v in ipairs(target_vocab) do
                    if not seen[v] then
                        options[#options + 1] = { text = v, value = v }
                        seen[v] = true
                    end
                end
                options[#options + 1] = { text = "(unset — fall through)", value = UNSET }
            else
                options = _build_anim_event_options(entry.char_key, source_event, default_value)
            end

            sub_widgets[#sub_widgets + 1] = {
                setting_id    = sid,
                type          = "dropdown",
                default_value = default_value,
                options       = options,
            }
            _setting_index[sid] = {
                port_id       = entry.port_id,
                template_name = entry.template_name,
                kind          = "anim_event",
                source_event  = source_event,
                receiver_char = entry.char_key,
                -- v0.12.118: see the wield rec note — powers boot re-apply.
                default_value = default_value,
            }
        end
    end

    return {
        setting_id  = _sid_group(entry.port_id),
        type        = "group",
        sub_widgets = sub_widgets,
    }, tpl_present
end

-- Top-level entry point called by the lead. Internal structure:
--
--   wt_dev_anim_picker (group)
--     ├─ wt_dev_anim_char_kruber (group)
--     │    ├─ <port group 1>
--     │    ├─ <port group 2>
--     │    └─ ...
--     ├─ wt_dev_anim_char_saltzpyre (group)
--     ├─ wt_dev_anim_char_wh_priest (group)
--     ├─ wt_dev_anim_char_bardin    (group)
--     ├─ wt_dev_anim_char_kerillian (group)
--     └─ wt_dev_anim_char_sienna    (group)
--
-- Empty character buckets are SKIPPED — v0.12.97-dev empty-bucket-skip rule
-- (VMF errors at init with "must have at least 1 sub_widget" when a `group`
-- widget has zero `sub_widgets`).
function M.build_widget_tree()
    _setting_index = {}
    _ensure_catalog_built() -- safe to call from build_widget_tree even pre-install

    -- Bucket: char_key -> list of port-group widgets
    local buckets = {}
    for _, key in ipairs(_CHARACTER_ORDER) do buckets[key] = {} end

    for _, entry in ipairs(_CATALOG) do
        local grp, tpl_present = _build_port_group(entry)
        if not tpl_present then
            mod:warning("[wt:dev_anim] entry references missing Weapons.%s — submenu surfaced anyway",
                entry.template_name)
        end
        -- Skip ports that ended up with zero sub_widgets (target set + no
        -- source actions → empty group → VMF would reject at init).
        if grp and grp.sub_widgets and #grp.sub_widgets > 0 and buckets[entry.char_key] then
            buckets[entry.char_key][#buckets[entry.char_key] + 1] = grp
        elseif grp then
            mod:warning("[wt:dev_anim] port %s has zero sub_widgets — skipping (target set with no source actions?)",
                entry.port_id)
        end
    end

    local char_groups = {}
    for _, char_key in ipairs(_CHARACTER_ORDER) do
        if #buckets[char_key] > 0 then
            char_groups[#char_groups + 1] = {
                setting_id  = _sid_char_group(char_key),
                type        = "group",
                sub_widgets = buckets[char_key],
            }
        end
    end

    -- v0.12.99-dev: guard against empty top-level group. If every character
    -- bucket dropped (catalog is empty — e.g. all pairs CWV-managed, or the
    -- unlock data file failed to load), DON'T return a `type = "group"` with
    -- zero `sub_widgets` — VMF rejects that at init with "must have at least
    -- 1 sub_widget" and the entire mod fails to load. Return nil instead;
    -- the lead's _data.lua integration nil-checks before appending. This
    -- bug class burned us at v0.12.96-dev (empty character bucket) and
    -- v0.12.98-dev (empty top-level group when unlock_map was nil); the
    -- /wt_regression_test gate now scans every group for empty sub_widgets
    -- as a permanent guard.
    if #char_groups == 0 then
        mod:warning("[wt:dev_anim] catalog is empty after all filters — picker not surfaced. If this is unexpected, check mod:dofile of wt_unlock_data.lua and the CWV-managed filter list.")
        return nil
    end

    return {
        setting_id  = "wt_dev_anim_picker",
        type        = "group",
        sub_widgets = char_groups,
    }
end

-- Idempotent catalog builder. Defers to install-time wrapping in case
-- build_widget_tree is called before install (the lead calls it from
-- _data.lua, which is loaded BEFORE the main file finishes — but
-- ItemMasterList and Weapons are populated by the engine before any mod
-- code runs, so it's safe). The vocab tables also need Weapons + IML so we
-- build them here too.
local _catalog_built = false
function _ensure_catalog_built()
    if _catalog_built then return end

    -- Vocabs first — port groups read them.
    local native_templates = _build_native_templates_by_char()
    _live_wield_vocab      = _build_live_wield_vocab(native_templates)
    _live_anim_event_vocab = _build_live_anim_event_vocab(native_templates)

    _CATALOG = _build_dynamic_catalog()
    _catalog_built = true

    _dbg("catalog built: %d entries", #_CATALOG)
    for _, char_key in ipairs(_CHARACTER_ORDER) do
        local n = 0
        for _, entry in ipairs(_CATALOG) do
            if entry.char_key == char_key then n = n + 1 end
        end
        _dbg("  %s: %d port(s)", char_key, n)
    end
end

-- ---------------------------------------------------------------------------
-- Localization
-- ---------------------------------------------------------------------------

function M.loc_keys()
    _ensure_catalog_built()

    local keys = {
        wt_dev_anim_picker = { en = "Dev: 3P Animation Picker" },
    }

    for _, char_key in ipairs(_CHARACTER_ORDER) do
        keys[_sid_char_group(char_key)] = { en = _CHARACTER_LABEL[char_key] or char_key }
    end

    -- v0.12.100-dev: register loc keys for every dropdown option `text` value.
    -- VMF wraps unknown loc keys in `<>` brackets when rendering dropdowns,
    -- which surfaced as the "internal names in <>" bug. We pre-register each
    -- text-as-its-own-en-string so VMF localizes verbatim and the user sees
    -- the actual event name.
    local function _register_self(text)
        if text and not keys[text] then keys[text] = { en = text } end
    end

    _register_self("(unset — fall through)")

    -- Register every vocab value (wield + anim event vocabs, all chars).
    for _, vocab in pairs(_live_wield_vocab) do
        for _, v in ipairs(vocab) do _register_self(v) end
    end
    for _, vocab in pairs(_live_anim_event_vocab) do
        for _, v in ipairs(vocab) do _register_self(v) end
    end

    for _, entry in ipairs(_CATALOG) do
        keys[_sid_group(entry.port_id)] = { en = entry.label }

        -- Wield loc key — ONLY when no target is decided (the dropdown only
        -- surfaces in that case). v0.12.101-dev: targeted ports drop the
        -- wield dropdown so a loc key would be unused.
        if not entry.target_template then
            keys[_sid_wield(entry.port_id)] = { en = "Wield event" }
        end

        local tpl = Weapons and rawget(Weapons, entry.template_name)
        if tpl and tpl.wield_anim_career_3p then
            for _, career in ipairs(entry.careers) do
                local v = tpl.wield_anim_career_3p[career]
                if type(v) == "string" then
                    _register_self(v)
                    _register_self(v .. " (current)")
                end
            end
        end

        -- Register target-weapon vocab values so the dropdowns render their
        -- option text instead of being VMF-wrapped as `<value>`.
        if entry.target_template then
            local target_vocab = _collect_target_anim_event_vocab(entry.target_template)
            for _, v in ipairs(target_vocab) do
                _register_self(v)
                _register_self(v .. " (current)")
            end
        end

        local source_events = _collect_source_anim_events(entry.template_name)
        if source_events then
            for _, source_event in ipairs(source_events) do
                keys[_sid_anim_event(entry.port_id, source_event)] = {
                    en = "Animation for source action `" .. source_event .. "`",
                }
                -- Source-event variants used by _build_anim_event_options
                -- (only triggered on UNFILTERED dropdowns; for targeted ports
                -- these aren't surfaced, but registering them is harmless).
                _register_self(source_event)
                _register_self(source_event .. " (source — passthrough)")
                local cur = _first_anim_event_3p_for(entry.template_name, source_event)
                if type(cur) == "string" then
                    _register_self(cur)
                    _register_self(cur .. " (current)")
                end
            end
        end
    end

    return keys
end

-- ---------------------------------------------------------------------------
-- Live re-apply
-- ---------------------------------------------------------------------------

local function _dropdown_value_to_field(v)
    if v == nil or v == UNSET then return nil end
    return v
end

local function _apply_wield_change(rec, new_value)
    local tpl = Weapons and rawget(Weapons, rec.template_name)
    if not tpl then
        mod:warning("[wt:dev_anim] Weapons.%s missing; cannot apply wield change", rec.template_name)
        return false
    end
    tpl.wield_anim_career_3p = tpl.wield_anim_career_3p or {}
    local field_value = _dropdown_value_to_field(new_value)
    -- v0.12.100-dev: write to ALL careers on the receiver model (single
    -- dropdown drives N table entries since all same-model careers share
    -- the same skeleton/animations).
    local careers = rec.careers or {}
    for _, career in ipairs(careers) do
        tpl.wield_anim_career_3p[career] = field_value
    end
    _dbg("[apply] tpl=%s wield_anim_career_3p[%s careers] = %s",
        rec.template_name, #careers, tostring(field_value))
    return #careers > 0
end

local function _apply_anim_event_change(rec, new_value)
    local tpl = Weapons and rawget(Weapons, rec.template_name)
    if not tpl or not tpl.actions then
        mod:warning("[wt:dev_anim] Weapons.%s.actions missing; cannot apply anim_event change", rec.template_name)
        return 0
    end
    local field_value = _dropdown_value_to_field(new_value)
    local n = 0
    for _, action_group in pairs(tpl.actions) do
        if type(action_group) == "table" then
            for _, sub in pairs(action_group) do
                if type(sub) == "table" and sub.anim_event == rec.source_event then
                    sub.anim_event_3p = field_value
                    n = n + 1
                end
            end
        end
    end
    _dbg("[apply] tpl=%s source_event=%s -> anim_event_3p=%s (%d sub_actions mutated)",
        rec.template_name, rec.source_event, tostring(field_value), n)
    return n
end

-- Force a wield refresh so the engine re-fires `wield_anim_career_3p` /
-- re-reads `anim_event_3p` on the next animation event.
local function _try_force_rewield()
    local pm = Managers.player
    if not pm then return false, "Managers.player nil" end
    local player = pm:local_player()
    if not player then return false, "no local_player" end
    local unit = player.player_unit
    if not unit then return false, "no player_unit" end
    if not ScriptUnit or not ScriptUnit.has_extension then return false, "no ScriptUnit" end

    local inv = ScriptUnit.has_extension(unit, "inventory_system")
    if not inv then return false, "no inventory_system extension" end

    local slot
    if inv.get_wielded_slot_name then
        local ok, name = pcall(inv.get_wielded_slot_name, inv)
        if ok then slot = name end
    end
    if not slot then
        local equipment = inv._equipment or inv.equipment
        slot = equipment and equipment.wielded_slot
    end
    if not slot then return false, "no wielded_slot" end

    local ok, err = pcall(function() inv:wield(slot) end)
    if not ok then
        return false, "wield() raised: " .. tostring(err)
    end
    return true
end

function M.on_setting_changed(setting_id)
    local rec = _setting_index[setting_id]
    if not rec then return end -- not one of ours
    local new_value = mod:get(setting_id)

    local ok = false
    if rec.kind == "wield" then
        ok = _apply_wield_change(rec, new_value)
    elseif rec.kind == "anim_event" then
        local n = _apply_anim_event_change(rec, new_value)
        ok = n > 0
    end

    if not ok then return end

    local rw_ok, rw_err = _try_force_rewield()
    if not rw_ok then
        mod:info("[wt:dev_anim] applied %s = %s; couldn't auto-rewield (%s) — unwield/rewield manually to see change",
            setting_id, tostring(new_value), tostring(rw_err))
    else
        _dbg("[apply] auto-rewield OK for setting=%s value=%s", setting_id, tostring(new_value))
    end
end

-- ---------------------------------------------------------------------------
-- /wt_dump_anim_picks chat command
-- ---------------------------------------------------------------------------

local function _dump_port(entry)
    -- Sanitize port_id into an uppercase Lua-identifier-safe constant name.
    local pname = "_" .. entry.port_id:upper():gsub("[^A-Z0-9_]", "_")
    local tpl = Weapons and rawget(Weapons, entry.template_name)
    if not tpl then
        mod:info("-- ==== %s (template missing: %s) ====", entry.label, entry.template_name)
        return
    end

    mod:info("-- ==== %s (%s) ====", entry.label, entry.template_name)

    -- Wield block.
    mod:info("local %s_WIELD_3P = {", pname)
    local any_wield = false
    local wield = tpl.wield_anim_career_3p or {}
    for _, career in ipairs(entry.careers) do
        local v = wield[career]
        if v then
            mod:info("    %-18s = %q,", career, v)
            any_wield = true
        end
    end
    if not any_wield then
        mod:info("    -- (no wield_anim_career_3p entries set)")
    end
    mod:info("}")

    -- Remap block.
    local source_events = _collect_source_anim_events(entry.template_name)
    if source_events and #source_events > 0 then
        mod:info("local %s_ANIM_REMAP_3P = {", pname)
        local any_remap = false
        for _, source_event in ipairs(source_events) do
            local target = _first_anim_event_3p_for(entry.template_name, source_event)
            if target then
                mod:info("    %-28s = %q,", source_event, target)
                any_remap = true
            end
        end
        if not any_remap then
            mod:info("    -- (no anim_event_3p remaps set — strict-subset port)")
        end
        mod:info("}")
    end

    mod:info("") -- blank line between ports
end

local function _register_dump_command()
    mod:command("wt_dump_anim_picks",
        "Dump current 3P anim picker values as Lua-pastable snippets (optional: filter by character key)",
        function(filter_char)
            _ensure_catalog_built()
            mod:info("-- ==== wt 3P Anim Picker dump (%d ports) ====", #_CATALOG)
            for _, char_key in ipairs(_CHARACTER_ORDER) do
                if not filter_char or filter_char == char_key then
                    for _, entry in ipairs(_CATALOG) do
                        if entry.char_key == char_key then
                            _dump_port(entry)
                        end
                    end
                end
            end
            mod:info("-- ==== end dump ====")
            mod:echo("Anim picker dump written to console log.")
        end)
end

-- ---------------------------------------------------------------------------
-- /wt_coverage probe (v0.12.119) — PROJECT_STANDARDS §3.7 data harness
-- ---------------------------------------------------------------------------
-- Walks the picker catalog for the CURRENT character and reports, per port,
-- whether the wield event and every per-action anim_event_3p are actually
-- AUTHORED on the local 3P skeleton. One parseable line per port — this is the
-- in-game generator for weapon_tweaker/ANIMATION_COVERAGE.md statuses, so the
-- user runs one command per character instead of eyeballing every port.
-- Caveat: "authored" proves the clip exists, NOT that it plays visibly in
-- chain states (DEVELOPMENT.md "invisible playback") — final word is the eye.

local function _coverage_has_anim(unit, event)
    if type(event) ~= "string" or event == "" then return false end
    local ok, result = pcall(Unit.has_animation_event, unit, event)
    return ok and result == true
end

local function _register_coverage_command()
    mod:command("wt_coverage",
        "3P coverage probe for the CURRENT character: per-port wield + action events vs the local skeleton",
        function()
            _ensure_catalog_built()
            local pm = Managers and Managers.player
            local player = pm and pm:local_player()
            local unit = player and player.player_unit
            if not unit then
                mod:echo("[wt_coverage] no local player unit — run from the keep or a mission.")
                return
            end
            local career_ext = ScriptUnit and ScriptUnit.has_extension
                and ScriptUnit.has_extension(unit, "career_system")
            local career_name = career_ext and career_ext.career_name and career_ext:career_name()
            if not career_name then
                mod:echo("[wt_coverage] could not resolve current career.")
                return
            end

            local ports, full, partial, broken = 0, 0, 0, 0
            mod:info("[wt:coverage] ==== career=%s ====", career_name)
            for _, entry in ipairs(_CATALOG) do
                local applies = false
                for _, c in ipairs(entry.careers or {}) do
                    if c == career_name then applies = true; break end
                end
                if applies then
                    ports = ports + 1
                    local tpl = Weapons and rawget(Weapons, entry.template_name)
                    if not tpl then
                        broken = broken + 1
                        mod:info("[wt:coverage] port=%s tpl=%s STATUS=template_missing", entry.port_id, entry.template_name)
                    else
                        local wield = tpl.wield_anim_career_3p and tpl.wield_anim_career_3p[career_name]
                        local wield_ok = wield and _coverage_has_anim(unit, wield) or false
                        local total, authored, missing = 0, 0, {}
                        for _, action_group in pairs(tpl.actions or {}) do
                            if type(action_group) == "table" then
                                for _, sub in pairs(action_group) do
                                    if type(sub) == "table" and type(sub.anim_event_3p) == "string" then
                                        total = total + 1
                                        if _coverage_has_anim(unit, sub.anim_event_3p) then
                                            authored = authored + 1
                                        elseif #missing < 6 then
                                            missing[#missing + 1] = sub.anim_event_3p
                                        end
                                    end
                                end
                            end
                        end
                        local status
                        if (wield == nil or wield_ok) and authored == total then
                            status = "FULL"; full = full + 1
                        elseif authored > 0 or wield_ok then
                            status = "PARTIAL"; partial = partial + 1
                        else
                            status = "NONE"; broken = broken + 1
                        end
                        mod:info("[wt:coverage] port=%s tpl=%s wield=%s wield_authored=%s actions_3p=%d authored=%d missing={%s} STATUS=%s",
                            entry.port_id, entry.template_name, tostring(wield), tostring(wield_ok),
                            total, authored, table.concat(missing, ","), status)
                    end
                end
            end
            mod:info("[wt:coverage] ==== %d port(s): %d FULL, %d PARTIAL, %d NONE/missing ====",
                ports, full, partial, broken)
            mod:echo("[wt_coverage] %s: %d port(s) probed — %d full, %d partial, %d none. Details in console log.",
                career_name, ports, full, partial, broken)
        end)
end

-- ---------------------------------------------------------------------------
-- Boot re-apply of stored picks (v0.12.118)
-- ---------------------------------------------------------------------------
-- Before this, picker picks lived only in the VMF settings store: they applied
-- live via on_setting_changed but were NEVER replayed onto Weapons.* at boot,
-- so every tuned port silently reverted to patcher/template defaults on
-- restart until someone baked the values into source. This closes the user's
-- tune-in-game -> persists-across-sessions -> bake-when-happy loop.
--
-- Only settings the user EXPLICITLY changed are re-applied: a setting whose
-- stored value equals the rec's build-time default is skipped. This guard is
-- load-bearing — widget defaults are captured at _data.lua time, BEFORE main
-- wt.lua's template patchers run, so blindly re-applying every setting would
-- overwrite patcher output with stale pre-patcher state.
function M.reapply_stored_picks()
    local applied, skipped_missing = 0, 0
    for sid, rec in pairs(_setting_index) do
        local v = mod:get(sid)
        if v ~= nil and v ~= rec.default_value then
            local tpl = Weapons and rawget(Weapons, rec.template_name)
            if not tpl then
                skipped_missing = skipped_missing + 1
            elseif rec.kind == "wield" then
                if _apply_wield_change(rec, v) then applied = applied + 1 end
            elseif rec.kind == "anim_event" then
                if _apply_anim_event_change(rec, v) > 0 then applied = applied + 1 end
            end
        end
    end
    if applied > 0 or skipped_missing > 0 then
        -- Ungated: the user must be able to confirm their tuned picks are live
        -- this session without enabling Debug Logging.
        mod:info("[wt:dev_anim] boot re-apply: %d stored pick(s) applied%s. /wt_dump_anim_picks to export as source.",
            applied,
            skipped_missing > 0 and (", " .. skipped_missing .. " skipped (template missing)") or "")
    end
    return applied
end

-- ---------------------------------------------------------------------------
-- install()
-- ---------------------------------------------------------------------------

function M.install()
    if not Weapons then
        mod:warning("[wt:dev_anim] Weapons global nil at install; live-apply will warn until templates load.")
    end
    if not ItemMasterList then
        mod:warning("[wt:dev_anim] ItemMasterList global nil at install; catalog will be empty until tables load.")
    end

    _ensure_catalog_built()

    -- Per-port template existence check — surfaces partial-install + future
    -- gated-patcher cases.
    for _, entry in ipairs(_CATALOG) do
        if not (Weapons and rawget(Weapons, entry.template_name)) then
            mod:warning("[wt:dev_anim] Weapons.%s missing at install; submenu surfaced but live-apply is a no-op until template loads.",
                entry.template_name)
        end
    end

    _register_dump_command()
    _register_coverage_command()

    -- v0.12.118: replay user-tuned picks onto the live templates. install()
    -- runs at the END of main wt.lua — after every template patcher — so this
    -- layers user picks on top of patcher output, same as a live menu change.
    M.reapply_stored_picks()

    -- One-time install notification — log line only, no chat spam.
    local counts = {}
    for _, char_key in ipairs(_CHARACTER_ORDER) do
        local n = 0
        for _, entry in ipairs(_CATALOG) do
            if entry.char_key == char_key then n = n + 1 end
        end
        if n > 0 then counts[#counts + 1] = char_key .. "=" .. n end
    end
    mod:info("[wt:dev_anim] installed. %d ports (%s). /wt_dump_anim_picks to dump.",
        #_CATALOG, table.concat(counts, " "))

    if #_OPEN_QUESTIONS > 0 then
        mod:info("[wt:dev_anim] %d open question(s) from catalog build:", #_OPEN_QUESTIONS)
        for _, msg in ipairs(_OPEN_QUESTIONS) do
            mod:info("  - %s", msg)
        end
    end
end

return M
