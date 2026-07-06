local mod = get_mod("event_tweaker")
_MEM_PROBE_T0_EVT = collectgarbage("count")  -- [mem-probe] temp Lua-footprint baseline (lua_heap 1 GiB cap diagnostic)

local MOD_VERSION = "0.4.22-dev"

-- Startup banner: log-only, NOT chat. The applied marker line further down
-- ([event_tweaker] enabled v<X> settings_fp=<hash>) is the canonical version
-- surface (PROJECT_STANDARDS.md § 3.6 "Chat-echo policy").
mod:info("Tweaker: Events v%s loaded", MOD_VERSION)

-- Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6).
-- Both route through VMF's built-in logging system (gated by VMF output_mode_debug / output_mode_warning).
-- `_dbg` is for confirmation / expected behavior — mod:debug channel.
-- `_dbg_alert` is for unexpected / wrong / mismatch — mod:warning channel.
local function _dbg(fmt, ...)
    mod:debug("[event_tweaker:dbg] " .. fmt, ...)
end

local function _dbg_alert(fmt, ...)
    mod:warning("[event_tweaker:dbg] " .. fmt, ...)
end

-- ============================================================
-- Cursed Adventure — Chaos Wastes / Be'lakor curse catalog
-- (verified by adversarial source audit 2026-06-19 — see DEVELOPMENT.md
-- "Cursed Adventure" + CHANGELOG 0.4.14-dev)
-- ============================================================
-- The catalog lives in the shared require'd module event_tweaker_curses (also
-- required by _data.lua + _localization.lua) — it MUST NOT be a mod._field set
-- here, because VMF loads files localization -> data -> script (script LAST),
-- so a script-set field is nil at data/loc eval. These curses normally run only
-- inside the Chaos Wastes / Deus realm because their unit/decal resource
-- PACKAGE is loaded only by DeusRunState.set_event_mutators
-- (deus_run_state.lua:438-453); the mechanics themselves use only standard
-- mission managers and every DLC entity system is registered into EVERY mission
-- at boot (entity_system.lua:176 + :424-435). So once we preload the package on
-- every peer (the MutatorHandler.init + _activate_mutator hooks below), they run
-- on a plain adventure map. NB: clients ALSO need the package
-- (spawn_network_unit replicates a husk), so unlike the host-only "Other
-- Mutators" group, the Cursed Adventure group requires event_tweaker on EVERY peer.
local Curses                  = require("scripts/mods/event_tweaker/event_tweaker_curses")
local MANAGED_CURSES          = Curses.MANAGED_CURSES
local _CURSE_BROKEN_IN_ADVENTURE = Curses.BROKEN_IN_ADVENTURE
local _CURSE_TO_GOD           = Curses.CURSE_TO_GOD

-- Applied marker (PROJECT_STANDARDS.md § 3.6 "Applied marker line (universal)").
-- Walks the data widget tree, FNV-1a-32 hashes setting=value pairs, prints
-- one mod:info line at load. ALWAYS fires (operational telemetry).
local function _settings_fingerprint()
    local ok, data = pcall(require, "scripts/mods/event_tweaker/event_tweaker_data")
    if not ok or type(data) ~= "table" then return "nodata" end
    local keys = {}
    local function walk(node)
        if type(node) ~= "table" then return end
        if type(node.setting_id) == "string" then keys[#keys + 1] = node.setting_id end
        for _, child in pairs(node) do
            if type(child) == "table" then walk(child) end
        end
    end
    walk(data)
    if #keys == 0 then return "nosettings" end
    table.sort(keys)
    local parts = {}
    for i, k in ipairs(keys) do
        local v = mod:get(k)
        if v == true then       parts[i] = k .. "=1"
        elseif v == false then  parts[i] = k .. "=0"
        elseif v == nil then    parts[i] = k .. "=?"
        else                    parts[i] = k .. "=" .. tostring(v) end
    end
    local s = table.concat(parts, ";")
    local h = 2166136261
    for i = 1, #s do
        local byte = string.byte(s, i)
        local xored, place = 0, 1
        local hh, bb = h, byte
        for _ = 1, 32 do
            local hb, bbit = hh % 2, bb % 2
            if hb ~= bbit then xored = xored + place end
            place = place * 2
            hh = (hh - hb) / 2
            bb = (bb - bbit) / 2
        end
        h = (xored * 16777619) % 4294967296
    end
    return string.format("%08x", h)
end

mod:info("[event_tweaker:LOAD] v%s enabled fp=%s OK", MOD_VERSION, _settings_fingerprint())

-- Per PROJECT_STANDARDS § 3.6 + § 14a: dev/alpha/beta/0.x versions print
-- version to chat on load so the user can see what's active. Stable
-- (>=1.0.0) versions stay silent. Detect via MOD_VERSION string match.
if MOD_VERSION:find("-dev$") or MOD_VERSION:find("-alpha$") or MOD_VERSION:find("-beta$") or MOD_VERSION:find("-rc%d*$") or MOD_VERSION:find("^0%.") then
    mod:echo(string.format("[event_tweaker] v%s loaded", MOD_VERSION))
end

-- v0.4.6-dev: regression test scaffold (event_tweaker had none).
local _RT_CHECKS = {}
local function _rt_register(name, fn)
    _RT_CHECKS[#_RT_CHECKS + 1] = { name = name, fn = fn }
end
mod:command("event_tweaker_regression_test", "Run regression smoke checks for past bugs", function()
    local pass, fail = 0, 0
    mod:echo("=== event_tweaker regression_test (v%s) ===", MOD_VERSION)
    for _, c in ipairs(_RT_CHECKS) do
        local ok, err = pcall(c.fn)
        if ok and err == nil then
            mod:echo("  PASS: %s", c.name); pass = pass + 1
            mod:info("[regression] PASS %s", c.name)
        else
            local msg = (not ok and tostring(err)) or tostring(err)
            mod:echo("  FAIL: %s -- %s", c.name, msg); fail = fail + 1
            mod:warning("[regression] FAIL %s: %s", c.name, msg)
        end
    end
    mod:echo("=== %d passed, %d failed ===", pass, fail)
end)

_rt_register("dbg_helpers_two_channel", function()
    if type(_dbg) ~= "function" then return "_dbg helper missing" end
    if type(_dbg_alert) ~= "function" then return "_dbg_alert helper missing" end
    local ok = pcall(_dbg, "smoke test")
    if not ok then return "_dbg raised" end
    ok = pcall(_dbg_alert, "smoke test")
    if not ok then return "_dbg_alert raised" end
end)


_rt_register("localization_format_safe", function()
    -- Layer 3 (2026-05-25): catch unescaped %-format chars in loc strings at
    -- runtime. VMF's tooltip render path calls string.format on the loc value;
    -- literal "%APPDATA%" / "5%" / "%USERNAME%" raises 'invalid option' and
    -- shows as a red error tooltip in the VMF settings UI. Static check is
    -- qa/check_localization.ps1 -- this is its runtime twin so the bug can't
    -- ship even if the static check is skipped. RULE: any literal % in a loc
    -- string must be doubled to %%.
    local ok, loc = pcall(mod.dofile, mod, "scripts/mods/event_tweaker/event_tweaker_localization")
    if not ok or type(loc) ~= "table" then return end  -- can't reach loc; skip
    for k, v in pairs(loc) do
        if type(v) == "table" and type(v.en) == "string" then
            local fmt_ok, fmt_err = pcall(string.format, v.en)
            if not fmt_ok then
                return string.format(
                    "loc key %q has invalid format string (escape literal %% as %%%%): %s",
                    k, tostring(fmt_err))
            end
        end
    end
end)
_rt_register("suppress_live_event_default_off", function()
    -- v0.4.10-dev: ensure suppress_live_event defaults to false so existing
    -- users see no behavior change after upgrading. The data file's
    -- default_value=false is the source of truth; this check confirms
    -- the widget actually registered the default and mod:get returns it.
    local v = mod:get("suppress_live_event")
    -- VMF: an unregistered setting returns nil; both nil and false are
    -- "off" for our use, but a true here would mean someone shipped the
    -- mod with the wrong default.
    if v == true then
        return "suppress_live_event defaulted to true — must default off"
    end
end)

-- ============================================================
-- DLC ownership gate
-- ============================================================
-- Modded mods may unlock vanilla progression but must NOT bypass paid
-- DLC paywalls. Mutators / presets that ship as DLC are gated here at
-- the injection sites so the lobby never receives content the host
-- doesn't own. (The vanilla level-load path refuses to load the map
-- anyway; without this gate, picking a DLC preset you don't own
-- produces a confusing failure instead of a clean "not owned" no-op.)
--
-- DLC IDs taken from DLCSettings in
-- scripts/settings/dlc_settings.lua:274 (geheimnisnacht_2021),
-- :576 (geheimnisnacht_2025), :287 (skulls_2023). Vanilla gate
-- pattern: Managers.unlock:is_dlc_unlocked(dlc_id). Pre-check with
-- dlc_exists so an unknown id doesn't trip the fassert in
-- UnlockManager.is_dlc_unlocked (unlock_manager.lua:527).
local DLC_BY_MUTATOR = {
    geheimnisnacht_2021             = "geheimnisnacht_2021",
    geheimnisnacht_2021_hard_mode   = "geheimnisnacht_2021",
    skulls_2023                     = "skulls_2023",
}

local DLC_BY_PRESET = {
    geheimnisnacht_2021 = "geheimnisnacht_2021",
    -- 2025 / 2026 presets inject the 2021 mutator and the year-specific
    -- active_events string (the ritual-site engine keys off it via
    -- string.find in geheimnisnacht_utils.lua:103). Both DLCs need to
    -- be owned for the preset to do anything useful; gate on the
    -- seasonal-content DLC (geheimnisnacht_<year>). DLC IDs verified
    -- in dlc_settings.lua:597 (skulls_2026) and :606 (geheimnisnacht_2026).
    geheimnisnacht_2025 = "geheimnisnacht_2025",
    geheimnisnacht_2026 = "geheimnisnacht_2026",
    skulls_2023         = "skulls_2023",
    skulls_2026         = "skulls_2026",
}

local function owns_dlc(dlc_id)
    if not dlc_id then
        return true
    end
    local um = rawget(_G, "Managers") and Managers.unlock
    if not um then
        -- Unlock manager not constructed yet. Fail closed: if we can't
        -- verify ownership, don't inject. Hooks rerun on every level
        -- load, so once Managers.unlock exists the gate evaluates normally.
        return false
    end
    if um.dlc_exists and not um:dlc_exists(dlc_id) then
        return false
    end
    return um:is_dlc_unlocked(dlc_id)
end

local function mutator_allowed(mutator_id)
    local dlc = rawget(DLC_BY_MUTATOR, mutator_id)
    return owns_dlc(dlc)
end

local function preset_allowed(preset_id)
    local dlc = rawget(DLC_BY_PRESET, preset_id)
    return owns_dlc(dlc)
end

-- ============================================================
-- Mutator catalog (kept in sync with event_tweaker_data.lua's copy)
-- ============================================================
-- Names match NetworkLookup.mutator_templates entries registered
-- year-round via DLCUtils.append("mutators") in mutator_settings.lua
-- plus DLC common settings (mutators_batch_01/02/04, geheimnisnacht_2021,
-- skulls_2023). NB: keep this list in sync with event_tweaker_data.lua
-- — both iterate over it. (No cross-file require because VMF mod-script /
-- mod-data load order isn't documented and the sibling tweaker mods all
-- keep state file-local.)
local MUTATOR_CATALOG = {
    { id = "cat_difficulty", mutators = {
        "no_ammo", "no_pickups", "player_dot", "instant_death",
        "no_respawn", "elite_run", "shared_health_pool",
        "whiterun", "realism",
    }},
    { id = "cat_specials", mutators = {
        "specials_frequency", "more_specials", "same_specials",
        "big_specials", "elite_specials", "gutter_runner_mayhem",
        "chaos_warriors_trickle", "mixed_horde", "multiple_bosses",
        "hordes_galore", "powerful_elites", "skulking_sorcerer",
    }},
    { id = "cat_hordes", mutators = {
        "wave_of_plague_monks", "wave_of_berzerkers", "high_intensity",
        "splitting_enemies", "explosive_loot_rats", "bloodlust",
    }},
    { id = "cat_atmosphere", mutators = {
        "night_mode", "darkness", "ticking_bomb",
        "flames", "lightning_strike", "chasing_spirits",
    }},
    { id = "cat_objectives", mutators = { "escort", "slayer_curse", "leash" }},
    { id = "cat_winds", mutators = {
        "life", "metal", "heavens", "light",
        "shadow", "fire", "death", "beasts",
    }},
    { id = "cat_events", mutators = {
        "geheimnisnacht_2021", "geheimnisnacht_2021_hard_mode",
        "skulls_2023",
    }},
}

-- ============================================================
-- Event presets
-- ============================================================
-- A preset bundles two pieces of fabricated live-event state:
--   active_events  -- list of event-name strings; some mutator
--                     server_start_function calls do string.find
--                     against these. mutator_geheimnisnacht_2021
--                     uses this to decide which 5 maps spawn
--                     ritual sites (see scripts/settings/dlcs/
--                     geheimnisnacht_2025/geheimnisnacht_utils.lua).
--   mutators       -- name strings to inject into the lobby's
--                     mutator list via append_live_event_mutators.
-- skulls_2023's mutator does NOT inspect active_events — it spawns
-- skull pickups unconditionally inside its own server_start_function.
-- We still set active_events for completeness / future-proofing.
local EVENT_PRESETS = {
    geheimnisnacht_2021 = {
        active_events = { "geheimnisnacht_2021" },
        mutators      = { "geheimnisnacht_2021" },
        -- Pre-baked decorated keep level loaded by AdventureMechanism on startup.
        -- Names confirmed in scripts/settings/level_settings.lua: inn_level_halloween,
        -- inn_level_skulls, inn_level_celebrate, inn_level_sonnstill.
        hub_level = "inn_level_halloween",
    },
    geheimnisnacht_2025 = {
        active_events = { "geheimnisnacht_2025" },
        mutators      = { "geheimnisnacht_2021" },
        hub_level     = "inn_level_halloween",
    },
    -- 2026 = same mutator + hub as prior years; only the active_events
    -- string differs (drives the year's 5-map list in geheimnisnacht_
    -- utils.lua:43-49: farmlands, dlc_wizards_tower, catacombs, bell,
    -- ussingen). Added v0.4.11-dev once Fatshark shipped the 2026 maps.
    geheimnisnacht_2026 = {
        active_events = { "geheimnisnacht_2026" },
        mutators      = { "geheimnisnacht_2021" },
        hub_level     = "inn_level_halloween",
    },
    skulls_2023 = {
        active_events = { "skulls_2023" },
        mutators      = { "skulls_2023" },
        hub_level     = "inn_level_skulls",
    },
    -- skulls_2026: vanilla skulls mutator is unchanged (no mutator_
    -- skulls_2026 file in source — Fatshark only added cosmetics +
    -- portraits for 2026, not new gameplay). active_events string set
    -- for consistency; the skulls mutator is self-contained and doesn't
    -- inspect active_events.
    skulls_2026 = {
        active_events = { "skulls_2026" },
        mutators      = { "skulls_2023" },
        hub_level     = "inn_level_skulls",
    },
}

-- ============================================================
-- Selection accumulators
-- ============================================================

local function active_preset()
    local pick = mod:get("event_preset")
    if not pick or pick == "off" then
        return nil
    end
    -- DLC paywall gate: if the preset's DLC isn't owned, treat as "off".
    -- Don't inject; the vanilla level-load path would refuse the map anyway.
    if not preset_allowed(pick) then
        return nil
    end
    return EVENT_PRESETS[pick]
end

-- ============================================================
-- Dynamic mutator discovery (ported from "Deed Mutators Selector",
-- Workshop 3579882542)
-- ============================================================
-- That mod's whole feature is iterating the live MutatorTemplates global and
-- surfacing every mutator the engine flags as player-facing (carries BOTH a
-- display_name and a description). MUTATOR_CATALOG above is a curated,
-- hand-tooltipped subset; this picks up everything else SAFE for adventure.
--
-- TWO engine-flag exclusions keep the "Other Mutators" group adventure-safe:
--   1. tmpl.packages — a non-empty packages list means the mutator spawns
--      units/decals from a resource package loaded ONLY by
--      DeusRunState.set_event_mutators (deus_run_state.lua:438-453) in the
--      Chaos Wastes / Deus realm. AdventureMechanism never loads it, so
--      activating one on a standard Adventure mission spawns from an unloaded
--      package -> hard "Resource not found" fatal. Those package-bearing
--      curses are surfaced SEPARATELY in the "Cursed Adventure" group, which
--      preloads the package first (see the curse-adventure section below).
--   2. tmpl.hide_from_player_ui — Fatshark's explicit "not player-facing"
--      flag (the hidden Deus pacing knobs). A stricter signal than the
--      display_name+description heuristic Deed Mutators Selector relied on.
--
-- Network safety: NetworkLookup.mutator_templates = create_lookup({}, MutatorTemplates)
-- (network_lookup.lua:266) is built at boot from the full template table, so
-- every boot-registered name is a valid rpc_activate_mutator_client arg and
-- broadcasts to vanilla clients (the safe group stays host-only).
local function _is_adventure_safe_mutator(name, tmpl)
    return type(tmpl) == "table"
        and tmpl.display_name and tmpl.description
        and not tmpl.hide_from_player_ui
        and not (tmpl.packages and next(tmpl.packages))
        and not _CURSE_BROKEN_IN_ADVENTURE[name]   -- weave/deus-only crashers
end

local _displayable_cache
local function displayable_registered_mutators()
    if _displayable_cache then
        return _displayable_cache
    end
    local out = {}
    local MT = rawget(_G, "MutatorTemplates")
    -- Require a NON-EMPTY table: don't memoize an empty set if this is ever
    -- called before the settings tables finish populating.
    if MT and next(MT) then
        for name, tmpl in pairs(MT) do
            if _is_adventure_safe_mutator(name, tmpl) then
                out[name] = true
            end
        end
        _displayable_cache = out
    end
    return out
end

-- Package-bearing curse mutators whose checkbox is on. DLC-owned (free CW /
-- Be'lakor content, so always true) + actually registered in MutatorTemplates.
-- These ride the SAME live-event injection as everything else, but additionally
-- trigger per-peer package preload + cursed-sky lighting (hooks near EOF).
local function selected_curse_mutators()
    local out = {}
    local MT = rawget(_G, "MutatorTemplates")
    for i = 1, #MANAGED_CURSES do
        local c = MANAGED_CURSES[i]
        if mod:get("mut_" .. c.id) and owns_dlc(c.dlc)
           and (not MT or rawget(MT, c.id)) then
            out[#out + 1] = c.id
        end
    end
    return out
end

-- Returns a flat list of mutator names whose individual checkboxes are on —
-- the curated catalog PLUS every dynamically-discovered adventure-safe mutator,
-- deduped. DLC-gated mutators owned by the host pass; un-owned ones are
-- dropped so they never reach the lobby. (Package-bearing curses are handled
-- separately by selected_curse_mutators() — they aren't in this set.)
local function selected_individual_mutators()
    local out, seen = {}, {}
    local function consider(id)
        if not seen[id] and mod:get("mut_" .. id) and mutator_allowed(id) then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    for ci = 1, #MUTATOR_CATALOG do
        local cat = MUTATOR_CATALOG[ci]
        for mi = 1, #cat.mutators do
            consider(cat.mutators[mi])
        end
    end
    for id in pairs(displayable_registered_mutators()) do
        consider(id)
    end
    return out
end

_rt_register("dynamic_mutator_discovery", function()
    -- Confirms the Deed-Mutators-Selector port is live: discovery must surface
    -- adventure-safe mutators BEYOND the curated catalog, else "Other Mutators"
    -- ships empty. Skips cleanly when the template table isn't loaded.
    local MT = rawget(_G, "MutatorTemplates")
    if not MT then return end
    local curated = {}
    for ci = 1, #MUTATOR_CATALOG do
        for mi = 1, #MUTATOR_CATALOG[ci].mutators do
            curated[MUTATOR_CATALOG[ci].mutators[mi]] = true
        end
    end
    for id in pairs(displayable_registered_mutators()) do
        if not curated[id] then return end
    end
    return "no uncurated adventure-safe mutators discovered — Other Mutators group would be empty"
end)

-- Combine preset mutators + individual checkbox mutators, deduped.
local function gather_mutators()
    local seen = {}
    local out = {}
    local function add(name)
        if not seen[name] then
            seen[name] = true
            out[#out + 1] = name
        end
    end

    local preset = active_preset()
    if preset and preset.mutators then
        for i = 1, #preset.mutators do
            local name = preset.mutators[i]
            -- Defense-in-depth: even though active_preset() already
            -- returns nil for un-owned preset DLCs, re-check each
            -- mutator in case a preset bundles a mutator gated by a
            -- different DLC than the preset itself.
            if mutator_allowed(name) then
                add(name)
            end
        end
    end

    local individual = selected_individual_mutators()
    for i = 1, #individual do
        add(individual[i])
    end

    -- Package-bearing Chaos Wastes / Be'lakor curses. Same injection path; the
    -- MutatorHandler._activate_mutator hook preloads their package on each peer.
    local curses = selected_curse_mutators()
    for i = 1, #curses do
        add(curses[i])
    end

    return out
end

local function gather_active_events()
    local preset = active_preset()
    if not preset or not preset.active_events then
        return nil
    end
    return preset.active_events
end

-- v0.4.10-dev: when on, the three live-event hooks drop Fatshark's original
-- response before merging our own injections. Lets the host neutralize the
-- currently-live Fatshark event (e.g. Skulls 2026 keep decor + Geheimnisnacht
-- 2026 ritual sites & mission lighting) without having to wait it out.
-- Default false — keeps prior pass-through behavior for anyone happy with
-- the additive-only semantics.
local function suppress_live_event()
    return mod:get("suppress_live_event") and true or false
end

-- ============================================================
-- List merge helper
-- ============================================================

local function merge_lists(original, extra)
    if not extra or #extra == 0 then
        return original
    end
    if not original or #original == 0 then
        return extra
    end
    local merged = table.clone(original)
    for i = 1, #extra do
        merged[#merged + 1] = extra[i]
    end
    return merged
end

-- ============================================================
-- Hooks
-- ============================================================
-- Both functions live on BackendInterfaceLiveEventsPlayfab. There is
-- only one interface implementation (no derived classes), so the
-- string-form mod:hook patches the prototype that all instances see
-- through __index lookup.
--
-- get_special_events feeds GameModeBase.append_live_event_mutators
-- (game_mode_base.lua:264) AND DialogueSystem.on_add_extension at
-- dialogue_system.lua:196-212. The dialogue system reads
-- `event_data.name` and uses it as a key in `_global_context`, so
-- the injected entry MUST include a non-nil string `name` or the
-- game crashes on startup ("table index is nil").

mod:hook("BackendInterfaceLiveEventsPlayfab", "get_special_events", function (func, self)
    local original = func(self)
    local suppress = suppress_live_event()
    -- Suppress wins over Fatshark's list: drop their entries entirely so
    -- append_live_event_mutators sees only ours. Defense-in-depth — also
    -- short-circuits the DialogueSystem read path so no Fatshark event
    -- ambient dialogue plays.
    if suppress then
        original = nil
    end
    local mutators = gather_mutators()
    if #mutators == 0 then
        -- Original is either Fatshark's list (suppress off) or nil
        -- (suppress on with no injection of our own). Log the pass-through so
        -- the log unambiguously shows event_tweaker injected NOTHING and what
        -- (if anything) Fatshark is serving — distinguishes "ET caused it" from
        -- "a real live event" when debugging.
        local orig = {}
        if type(original) == "table" then
            for i = 1, #original do
                local e = original[i]
                orig[i] = (type(e) == "table" and tostring(e.name)) or tostring(e)
            end
        end
        mod:debug("[event-inject] injecting NOTHING (no preset/mutator/curse selected); suppress=%s; Fatshark special_events pass-through=[%s]",
            tostring(suppress), table.concat(orig, ","))
        return original or {}
    end
    -- Use the preset name if one is selected (matches the active_events
    -- string), else a synthetic identifier. Either way it must be a
    -- string — see comment above.
    local preset_pick = mod:get("event_preset")
    local injected_name = (preset_pick and preset_pick ~= "off")
        and preset_pick
        or "event_tweaker_custom"
    -- v0.4.2 defensive logging: log every injected mutator + the preset name.
    -- Helps diagnose unexpected mutator interactions (e.g. "Horn of Magnus had
    -- no pickups" → was a special_event injection accidentally appending an
    -- incompatible mutator?). Fires once per get_special_events call, which
    -- happens on mission load + keep transitions. v0.4.10-dev added the
    -- `suppress=` field so leak-through is verifiable from the log.
    mod:info("[event-inject] preset=%s suppress=%s injecting %d mutator(s): [%s]",
        tostring(injected_name), tostring(suppress), #mutators, table.concat(mutators, ","))
    local injected = {
        {
            name         = injected_name,
            weekly_event = "append",
            mutators     = mutators,
        },
    }
    return merge_lists(original, injected)
end)

mod:hook("BackendInterfaceLiveEventsPlayfab", "get_active_events", function (func, self)
    local original = func(self)
    if suppress_live_event() then
        -- Drop Fatshark's strings so mutator_geheimnisnacht_2021's
        -- `string.find(live_event, "geheimnisnacht_%d+")` ritual-site
        -- lookup (geheimnisnacht_2025/geheimnisnacht_utils.lua) gets
        -- no match and the ritual-site engine stays dormant.
        original = nil
    end
    local extra = gather_active_events()
    if not extra then
        return original or {}
    end
    return merge_lists(original, extra)
end)

-- Hub decoration. Vanilla Geheimnisnacht / Skulls / Anniversary decorate the
-- keep by swapping the entire keep level file (inn_level_halloween,
-- inn_level_skulls, etc.) — the decorations are baked geometry, not runtime
-- spawns. The active level is decided by AdventureMechanism.get_starting_level
-- (adventure_mechanism.lua:625), which reads
-- `Managers.backend:get_level_variation_data().hub_level`. Hook that single
-- entry point so every consumer (StateIngame's keep flow events, interactions,
-- carousel) sees the override consistently.
--
-- Timing caveat: get_starting_level is queried at game launch and on each
-- keep-load. Changing the preset after the keep is already loaded won't swap
-- the keep — the user has to either restart the game OR start a mission and
-- return.
mod:hook("BackendManagerPlayFab", "get_level_variation_data", function (func, self)
    local original = func(self) or {}
    local preset = active_preset()
    local want_hub
    if preset and preset.hub_level then
        want_hub = preset.hub_level
    elseif suppress_live_event() then
        -- v0.4.10-dev: when suppress is on with no preset, pin keep to the
        -- vanilla default (adventure_mechanism.lua:7 HUB_LEVEL_NAME).
        -- adventure_mechanism's get_starting_level (line 627) reads our
        -- merged.hub_level instead of Fatshark's seasonal one, so the keep
        -- decoration reverts cleanly.
        want_hub = "inn_level"
    end
    if not want_hub then
        return original
    end
    -- Don't mutate the original — it's possibly the cached EMPTY_TABLE.
    local merged = table.clone(original)
    merged.hub_level = want_hub
    return merged
end)

-- ============================================================
-- Injected-mutator conflict-settings sanitizer (issue 386)
-- ============================================================
-- Some vanilla mutators' update_conflict_settings write PLAIN NUMBERS into three
-- CurrentPacing fields. mutator_high_intensity.lua:12-14 is the canonical case:
--   CurrentPacing.delay_horde_threat_value        = 200
--   CurrentPacing.delay_specials_threat_value     = 200
--   CurrentPacing.delay_mini_patrol_threat_value  = 200
-- Those functions are dispatched by MutatorHandler.conflict_director_updated_settings
-- (mutator_handler.lua:567), which iterates the INITIALIZED mutator set
-- (self._mutators, populated at MutatorHandler:new / state_ingame.lua:2232) and is
-- called from ConflictDirector.refresh_conflict_director_patches
-- (conflict_director.lua:886) -- itself run from ConflictDirector.init line 94,
-- BEFORE init reads those same fields at lines 219-221:
--   self.delay_horde_threat_value = CurrentPacing.delay_horde_threat_value and
--     DifficultyTweak.converters.tweaked_delay_threat_value(difficulty, tweak,
--       CurrentPacing.delay_horde_threat_value) or math.huge
-- tweaked_delay_threat_value ALWAYS indexes its 3rd arg as a per-difficulty table
-- (difficulty_tweak.lua get_value_for_difficulty: `value_table[Difficulties[i]]`),
-- so a scalar there is an uncatchable "attempt to index a number value" fatal that
-- kills ConflictDirector.init and leaves the mission with zero AI (issue 386). In
-- plain vanilla Adventure these mutators aren't in the list, so the fields stay the
-- table-shaped base values (conflict_settings.lua keys normal..versus_base);
-- event_tweaker is what injects a scalar-writing mutator into the set.
--
-- Fix: a hook_safe on conflict_director_updated_settings runs AFTER the vanilla
-- body writes the scalars, still synchronously inside refresh_conflict_director_
-- patches, so BEFORE init's line 219 read. It converts any scalar left in those
-- three fields into a per-difficulty table. get_value_for_difficulty walks DOWN the
-- Difficulties list to index 1 == "normal", so keying the floor difficulty covers
-- EVERY difficulty; the resolved current difficulty is stamped too for clarity.
-- init then reads a table and resolves the intended magnitude (200) with no crash.
-- Host-only in effect (conflict_director_updated_settings early-returns on clients),
-- and a strict no-op whenever the fields are already tables -- i.e. whenever we
-- inject nothing, or on any pass after the first, the scan finds no scalar.
do
    -- The CurrentPacing fields ConflictDirector.init (conflict_director.lua:219-221)
    -- feeds to tweaked_delay_threat_value, i.e. treats as per-difficulty tables.
    local PACING_TABLE_FIELDS = {
        "delay_horde_threat_value",
        "delay_mini_patrol_threat_value",
        "delay_specials_threat_value",
    }

    -- Pure + testable. Convert any scalar-valued PACING_TABLE_FIELDS entry on
    -- `pacing` into { normal = v, [difficulty] = v }. Returns the list of fixed
    -- field names, or nil if nothing needed fixing (the no-op signal). Already-
    -- tabular fields are left untouched.
    local function _sanitize_pacing_scalars(pacing, difficulty)
        if type(pacing) ~= "table" then
            return nil
        end
        local fixed
        for i = 1, #PACING_TABLE_FIELDS do
            local field = PACING_TABLE_FIELDS[i]
            local v = pacing[field]
            if type(v) == "number" then
                -- normal == Difficulties[1] is the floor of get_value_for_difficulty's
                -- downward walk, so it resolves for every difficulty; the explicit
                -- current-difficulty key is belt-and-suspenders.
                local as_table = { normal = v }
                if difficulty then
                    as_table[difficulty] = v
                end
                pacing[field] = as_table
                fixed = fixed or {}
                fixed[#fixed + 1] = field
            end
        end
        return fixed
    end
    mod._et386_sanitize_pacing_scalars = _sanitize_pacing_scalars  -- exposed for the regression check

    local function _current_difficulty()
        local dm = rawget(_G, "Managers") and Managers.state and Managers.state.difficulty
        if not dm or not dm.get_difficulty then
            return nil
        end
        local ok, difficulty = pcall(dm.get_difficulty, dm)
        if ok then
            return difficulty
        end
        return nil
    end

    -- Names of INITIALIZED mutators carrying an update_conflict_settings -- the
    -- candidates that could have written a scalar this pass. For the evidence line.
    local function _conflict_writing_mutators(self)
        local names, MT = {}, rawget(_G, "MutatorTemplates")
        local mutators = self and self._mutators
        if type(mutators) == "table" then
            for name, data in pairs(mutators) do
                local tmpl = (data and data.template) or (MT and rawget(MT, name))
                if tmpl and tmpl.update_conflict_settings then
                    names[#names + 1] = name
                end
            end
        end
        table.sort(names)
        return names
    end

    -- hook_safe fires AFTER the vanilla body writes the scalars, still inside
    -- refresh_conflict_director_patches (conflict_director.lua:886) and thus before
    -- ConflictDirector.init line 219 reads the fields.
    mod:hook_safe("MutatorHandler", "conflict_director_updated_settings", function(self)
        local cp = rawget(_G, "CurrentPacing")
        local fixed = _sanitize_pacing_scalars(cp, _current_difficulty())
        if fixed and #fixed > 0 then
            local writers = _conflict_writing_mutators(self)
            printf("[event-inject:386] sanitized update_conflict_settings for [%s] (fields: %s)",
                table.concat(writers, ","), table.concat(fixed, ","))
        end
    end)

    _rt_register("issue386_sanitize_pacing_scalar_to_table", function()
        -- A stub mutator wrote a scalar (as mutator_high_intensity does). The
        -- sanitizer must turn it into an indexable per-difficulty table that
        -- ConflictDirector.init's get_value_for_difficulty walk resolves to the same
        -- value for any difficulty.
        local pacing = { delay_horde_threat_value = 200 }
        local fixed = _sanitize_pacing_scalars(pacing, "cataclysm")
        local converted = pacing.delay_horde_threat_value
        if type(converted) ~= "table" then
            return "scalar delay_horde_threat_value was not converted to a table"
        end
        if converted.normal ~= 200 then
            return "converted table missing floor key normal=200 (breaks low-difficulty walk)"
        end
        if converted.cataclysm ~= 200 then
            return "converted table missing explicit current-difficulty key"
        end
        if type(fixed) ~= "table" or fixed[1] ~= "delay_horde_threat_value" then
            return "sanitizer did not report the fixed field"
        end
        -- Strict no-op when the field is already a table (i.e. nothing injected).
        local already = { delay_specials_threat_value = { normal = 5 } }
        if _sanitize_pacing_scalars(already, "normal") ~= nil then
            return "sanitizer mutated an already-tabular field (must be a no-op)"
        end
        if type(already.delay_specials_threat_value) ~= "table" or already.delay_specials_threat_value.normal ~= 5 then
            return "sanitizer corrupted an already-tabular field"
        end
        return nil
    end)
end

-- ============================================================
-- Diagnostic commands
-- ============================================================

local function dump_list(label, list)
    if not list or #list == 0 then
        mod:echo("[event] %s: <empty>", label)
        return
    end
    for i = 1, #list do
        local v = list[i]
        if type(v) == "table" then
            local muts = v.mutators and table.concat(v.mutators, ",") or ""
            local lvls = v.level_keys and table.concat(v.level_keys, ",") or "all"
            mod:echo("[event] %s[%d]: weekly_event=%s mutators={%s} levels={%s}",
                label, i, tostring(v.weekly_event), muts, lvls)
        else
            mod:echo("[event] %s[%d]: %s", label, i, tostring(v))
        end
    end
end

mod:command("event_probe", "Dump live-event state from the host's backend interface", function()
    local interface = Managers.backend and Managers.backend:get_interface("live_events")
    if not interface then
        mod:echo("[event] no live_events interface yet")
        return
    end
    dump_list("active_events", interface:get_active_events())
    dump_list("special_events", interface:get_special_events())
    dump_list("weekly_events", interface:get_weekly_events())
    mod:echo("[event] preset: %s suppress=%s",
        tostring(mod:get("event_preset")),
        tostring(suppress_live_event()))
    local muts = gather_mutators()
    mod:echo("[event] would-inject mutators: {%s}", table.concat(muts, ","))
end)

mod:command("event_active", "List currently-active mutators in the loaded game mode", function()
    local game_mode = Managers.state and Managers.state.game_mode
    local handler = game_mode and game_mode._mutator_handler
    if not handler then
        mod:echo("[event] no mutator_handler (not in a level?)")
        return
    end
    local active = handler:activated_mutators()
    local n = 0
    for name, _ in pairs(active) do
        n = n + 1
        mod:echo("[event] active mutator: %s", name)
    end
    if n == 0 then
        mod:echo("[event] no active mutators")
    end
end)

mod:command("event_clear", "Uncheck every individual mutator (preset untouched)", function()
    local n, seen = 0, {}
    local function clear(id)
        if not seen[id] and mod:get("mut_" .. id) then
            seen[id] = true
            mod:set("mut_" .. id, false, false)
            n = n + 1
        end
    end
    for ci = 1, #MUTATOR_CATALOG do
        local cat = MUTATOR_CATALOG[ci]
        for mi = 1, #cat.mutators do
            clear(cat.mutators[mi])
        end
    end
    for id in pairs(displayable_registered_mutators()) do
        clear(id)
    end
    for i = 1, #MANAGED_CURSES do
        clear(MANAGED_CURSES[i].id)
    end
    mod:echo("[event] cleared %d mutators", n)
end)

-- ============================================================
-- Mid-game preset application
-- ============================================================
-- Three vanilla queries we hook (get_special_events, get_active_events,
-- get_level_variation_data) are all consulted at level-load time. So a
-- preset change between loads is dormant until the next level swap.
-- Solution: when the user changes the preset, reload the current level.
--   - In a mission: retry_level() — re-runs append_live_event_mutators on
--     the new mutator list and rebuilds the mutator handler.
--   - In the keep, when the preset's target hub_level differs from the
--     current one: set_next_level(new_hub_level) + promote_next_level_data()
--     so AdventureMechanism.get_starting_level picks up the swap.
--   - In the keep, same hub_level (or no preset): retry_level() reloads
--     the current keep, which re-runs DialogueSystem's get_special_events
--     read; cheap and consistent.
-- Host-only. Vanilla clients re-sync via the standard level-load path.

local function is_host()
    return Managers.player and Managers.player.is_server
end

local function current_level_key()
    local lth = Managers.level_transition_handler
    return lth and lth:get_current_level_key()
end

local function is_in_hub()
    local key = current_level_key()
    local settings = key and LevelSettings and LevelSettings[key]
    return settings and settings.hub_level == true
end

local function target_hub_level()
    local preset = active_preset()
    if preset and preset.hub_level then
        return preset.hub_level
    end
    -- v0.4.10-dev: with suppress on (no preset), pin to vanilla "inn_level"
    -- so toggling suppress on while standing in inn_level_skulls/halloween
    -- triggers a keep swap back to the plain inn.
    if suppress_live_event() then
        return "inn_level"
    end
    -- Suppress off, no preset: don't dictate. apply_now will take the
    -- retry_level() branch and let Fatshark's get_level_variation_data
    -- pass through unchanged.
    return current_level_key()
end

local function apply_now(reason)
    if not is_host() then
        mod:echo("[event] only the lobby host can apply mid-game (vanilla mutator RPC sync requires host trigger)")
        return false
    end

    local game_mode = Managers.state and Managers.state.game_mode
    if not game_mode then
        mod:echo("[event] no active game mode — change will apply on next level load")
        return false
    end

    local cur = current_level_key()
    if is_in_hub() then
        local want = target_hub_level()
        if want ~= cur then
            -- Hub-level swap. set_next_level + promote queues the load;
            -- state_ingame's update loop picks it up via needs_level_load()
            -- and triggers the "load_next_level" transition.
            local lth = Managers.level_transition_handler
            lth:set_next_level(want)
            lth:promote_next_level_data()
            mod:echo("[event] %s — swapping keep %s -> %s", reason or "applying preset", tostring(cur), tostring(want))
            return true
        end
    end

    -- Mission, or keep with no hub_level change. retry_level reloads the
    -- current level key; on the way back in, append_live_event_mutators
    -- re-reads our hooked get_special_events.
    Managers.state.game_mode:retry_level()
    mod:echo("[event] %s — reloading %s", reason or "applying preset", tostring(cur))
    return true
end

mod:command("event_apply", "Reload the current level so preset + mutator changes take effect", function()
    apply_now("manual apply")
end)

mod.on_setting_changed = function(setting_id)
    -- Auto-reload on preset change and on suppress toggle. Individual
    -- mutator toggles use `event_apply` — otherwise a quick pass of 5
    -- checkboxes would trigger 5 reloads.
    if setting_id == "event_preset" then
        apply_now("event_preset changed")
    elseif setting_id == "suppress_live_event" then
        apply_now("suppress_live_event changed")
    end
end

-- ============================================================
-- Cursed Adventure — package preload + cursed-sky lighting
-- ============================================================
-- Makes the package-bearing Chaos Wastes / Be'lakor curses (MANAGED_CURSES)
-- actually run on a standard adventure mission. Two hooks:
--   1. MutatorHandler._activate_mutator — a method called on the HOST (via
--      activate_mutators) AND on every CLIENT (via rpc_activate_mutator_client
--      -> activate_mutator), so each peer SYNC-loads the curse's resource
--      package locally, exactly as DeusRunState.set_event_mutators does per
--      peer. Clients need it too: spawn_network_unit replicates a husk whose
--      unit lives in that package. Sync load (Managers.package:load 4th arg
--      false) = ready before the first in-mission spawn; no async race.
--   2. CameraManager.shading_callback — per-frame ShadingEnvironment-var tint
--      for the active curse's Chaos god (profiles copied from
--      chaos_wastes_tweaker.lua:3247). Blends multiplicatively on the level's
--      baked atmosphere; the engine re-seeds every frame so it reverts for
--      free when no curse is active. Client-side cosmetic, no RPC.
-- Both are gated to the ADVENTURE mechanism so a real Chaos Wastes run (where
-- DeusRunState already loads the package and ct already tints) is untouched.
do
    local ET_CURSE_PKG_REF = "event_tweaker_curse_package"
    local _loaded_curse_packages = {}   -- pkg_name -> true (our refs to balance)
    local _active_curse_god = nil        -- cached for the per-frame shading hook

    local function _is_adventure_mechanism()
        local mm = rawget(_G, "Managers") and Managers.mechanism
        if not mm or not mm.current_mechanism_name then return true end
        local ok, name = pcall(mm.current_mechanism_name, mm)
        if not ok then return true end
        return name == "adventure"
    end

    -- Recompute which Chaos god (if any) the currently-active curses theme, for
    -- the sky tint. Cheap; called on activate/deactivate only. When several
    -- curses of different gods are active, the lowest curse-name alphabetically
    -- wins — DETERMINISTIC so every peer agrees on one tint (pairs() order is
    -- unspecified and would diverge host vs client).
    local function _refresh_active_curse_god()
        local gm = Managers.state and Managers.state.game_mode
        local handler = gm and gm._mutator_handler
        local active = handler and handler._active_mutators
        local candidates = {}
        if active then
            for name, _ in pairs(active) do
                if _CURSE_TO_GOD[name] then candidates[#candidates + 1] = name end
            end
        end
        table.sort(candidates)
        _active_curse_god = candidates[1] and _CURSE_TO_GOD[candidates[1]] or nil
    end

    local function _maybe_preload_curse_package(name)
        if not _is_adventure_mechanism() then return end
        local MT = rawget(_G, "MutatorTemplates")
        local tmpl = MT and rawget(MT, name)
        if not (tmpl and tmpl.packages and next(tmpl.packages) and _CURSE_TO_GOD[name]) then
            return
        end
        local pm = rawget(_G, "Managers") and Managers.package
        if not pm then return end
        for _, pkg in ipairs(tmpl.packages) do
            if not _loaded_curse_packages[pkg] and not pm:has_loaded(pkg, ET_CURSE_PKG_REF) then
                local ok = pcall(pm.load, pm, pkg, ET_CURSE_PKG_REF, nil, false)  -- false = SYNC
                if ok then
                    _loaded_curse_packages[pkg] = true
                    _dbg("[curse] preloaded %s for %s", pkg, name)
                else
                    _dbg_alert("[curse] FAILED to preload %s for %s", pkg, name)
                end
            end
        end
    end

    -- Hook BOTH the per-mutator activate (host loop + client RPC) and deactivate
    -- so the package is ready before activation and the god cache stays current.
    mod:hook("MutatorHandler", "_activate_mutator", function(func, self, name, ...)
        _maybe_preload_curse_package(name)
        local a, b = func(self, name, ...)
        if _CURSE_TO_GOD[name] then _refresh_active_curse_god() end
        -- Log EVERY mutator the handler activates (ours OR vanilla/Fatshark), so
        -- the log shows the full active set. Cross-reference with the
        -- [event-inject] line: a name here that also appears there is
        -- event_tweaker's; one here WITHOUT a matching inject is the base game's.
        _dbg("[mutator-active] '%s' (server=%s)", tostring(name), tostring(self._is_server))
        return a, b
    end)
    mod:hook("MutatorHandler", "_deactivate_mutator", function(func, self, name, ...)
        local a, b = func(self, name, ...)
        if _CURSE_TO_GOD[name] then _refresh_active_curse_god() end
        return a, b
    end)

    -- Hot-join safety. A client joining MID-mission instantiates already-spawned
    -- curse husks during game-object sync, which the engine performs BEFORE it
    -- sends the mutator-activate RPC (peer_states.lua) — so the _activate_mutator
    -- load above would arrive too late and World.spawn_unit on the unloaded
    -- package would hard-crash the joiner. MutatorHandler.init already knows the
    -- mutator list at construction (host: the `mutators` arg; client: the
    -- network-synced _initialized_mutator_map, populated BEFORE game objects), so
    -- preload here too — on every peer, ahead of any husk. Belt-and-suspenders
    -- with the _activate_mutator load (normal-join + host).
    mod:hook_safe("MutatorHandler", "init", function(self, mutators)
        local names = {}
        if type(mutators) == "table" then
            for i = 1, #mutators do names[mutators[i]] = true end
        end
        local map = self._initialized_mutator_map
        if type(map) == "table" then
            -- Shape is engine-internal; harvest any string key OR value as a
            -- candidate mutator name (name-keyed or id->name, both covered).
            for k, v in pairs(map) do
                if type(k) == "string" then names[k] = true end
                if type(v) == "string" then names[v] = true end
            end
        end
        for name in pairs(names) do
            _maybe_preload_curse_package(name)
        end
    end)

    -- Balance the package ref-count + clear the cache on mission exit (per peer).
    -- Only drop an entry whose unload actually succeeded (a pcall failure on a
    -- divergent ref must keep the entry so it isn't orphaned / silently leaked).
    mod:hook_safe("StateIngame", "on_exit", function(self)
        local pm = rawget(_G, "Managers") and Managers.package
        if pm then
            for pkg in pairs(_loaded_curse_packages) do
                if pcall(pm.unload, pm, pkg, ET_CURSE_PKG_REF) then
                    _loaded_curse_packages[pkg] = nil
                end
            end
        end
        _active_curse_god = nil
    end)

    -- Per-god multiplicative sky/atmosphere tints (copied verbatim from
    -- chaos_wastes_tweaker.lua:3247 _CURSE_SKY_PROFILES, user-tuned values).
    local _CURSE_SKY_PROFILES = {
        khorne = {
            skydome_tint_color = {1.32, 0.51, 0.44}, sun_color = {1.21, 0.76, 0.62},
            secondary_sun_color = {1.14, 0.65, 0.58}, ambient_tint = {1.04, 0.69, 0.62},
            ambient_tint_top = {1.14, 0.58, 0.51}, fog_color = {1.39, 0.48, 0.44},
            exposure_mul = 0.95,
        },
        nurgle = {
            skydome_tint_color = {0.78, 1.05, 0.55}, sun_color = {1.05, 1.02, 0.65},
            secondary_sun_color = {0.92, 0.98, 0.66}, ambient_tint = {0.88, 0.95, 0.68},
            ambient_tint_top = {0.82, 1.00, 0.60}, fog_color = {0.80, 1.05, 0.55},
            exposure_mul = 1.00,
        },
        tzeentch = {
            skydome_tint_color = {0.62, 0.76, 1.35}, sun_color = {1.39, 0.72, 0.44},
            secondary_sun_color = {1.28, 0.79, 0.55}, ambient_tint = {1.25, 0.86, 0.58},
            ambient_tint_top = {1.32, 0.76, 0.48}, fog_color = {0.76, 0.83, 1.21},
            exposure_mul = 1.04,
        },
        slaanesh = {
            skydome_tint_color = {1.35, 0.50, 1.15}, sun_color = {1.30, 0.85, 0.95},
            secondary_sun_color = {1.20, 0.65, 1.05}, ambient_tint = {1.15, 0.65, 1.05},
            ambient_tint_top = {1.30, 0.55, 1.20}, fog_color = {1.25, 0.40, 1.10},
            exposure_mul = 0.97,
        },
        belakor = {
            skydome_tint_color = {0.40, 0.25, 0.65}, sun_color = {0.50, 0.50, 0.85},
            secondary_sun_color = {0.55, 0.50, 0.90}, ambient_tint = {0.75, 0.65, 1.00},
            ambient_tint_top = {0.60, 0.55, 1.00}, fog_color = {0.40, 0.30, 0.75},
            exposure_mul = 0.92,
        },
    }

    local function _cursed_lighting_on()
        return mod:get("cursed_lighting") ~= false  -- default ON
    end

    if rawget(_G, "CameraManager") and rawget(_G, "ShadingEnvironment") then
        mod:hook_safe("CameraManager", "shading_callback", function(self, world, shading_env, viewport)
            -- Vanilla wraps its whole body in `if self._world == world` — only
            -- touch the shading_env of the world this camera owns (UI / preview /
            -- end-screen worlds also drive shading_callback). Mirror it.
            if self._world ~= world then return end
            if not _active_curse_god or not _cursed_lighting_on() then return end
            if not _is_adventure_mechanism() then return end  -- leave real CW runs to ct
            local profile = _CURSE_SKY_PROFILES[_active_curse_god]
            if not profile then return end
            local function mul_set(var)
                local t = profile[var]
                if not t then return end
                local v = ShadingEnvironment.vector3(shading_env, var)
                if v then
                    ShadingEnvironment.set_vector3(shading_env, var,
                        Vector3(v.x * t[1], v.y * t[2], v.z * t[3]))
                end
            end
            mul_set("skydome_tint_color"); mul_set("sun_color")
            mul_set("secondary_sun_color"); mul_set("ambient_tint")
            mul_set("ambient_tint_top"); mul_set("fog_color")
            if profile.exposure_mul and profile.exposure_mul ~= 1.0 then
                local cur = ShadingEnvironment.scalar(shading_env, "exposure")
                if cur then
                    ShadingEnvironment.set_scalar(shading_env, "exposure", cur * profile.exposure_mul)
                end
            end
        end)
    end
end

mod:info("[mem-probe] event_tweaker boot_lua=+%.1f MB (of ~1024 MB lua_heap cap)", (collectgarbage("count") - _MEM_PROBE_T0_EVT) / 1024)
