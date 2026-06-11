local mod = get_mod("event_tweaker")

local MOD_VERSION = "0.4.13-dev"
-- Startup banner: log-only, NOT chat. The applied marker line further down
-- ([event_tweaker] enabled v<X> settings_fp=<hash>) is the canonical version
-- surface (PROJECT_STANDARDS.md § 3.6 "Chat-echo policy").
mod:info("Tweaker: Events v%s loaded", MOD_VERSION)

-- Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6).
-- Both gate on `enable_debug_logging`. Both no-op when toggle is off.
-- `_dbg` is for confirmation / expected behavior — file only.
-- `_dbg_alert` is for unexpected / wrong / mismatch — file AND in-game chat.
local function _dbg(fmt, ...)
    if mod:get("enable_debug_logging") then
        mod:info("[event_tweaker:dbg] " .. fmt, ...)
    end
end

local function _dbg_alert(fmt, ...)
    if mod:get("enable_debug_logging") then
        mod:info("[event_tweaker:dbg] " .. fmt, ...)
        mod:echo("[event_tweaker] " .. fmt, ...)
    end
end

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
    local saved = mod:get("enable_debug_logging")
    if saved ~= false then mod:set("enable_debug_logging", false) end
    local ok = pcall(_dbg, "smoke test off")
    if not ok then return "_dbg raised with toggle off" end
    ok = pcall(_dbg_alert, "smoke test off")
    if not ok then return "_dbg_alert raised with toggle off" end
    if saved == true then mod:set("enable_debug_logging", true) end
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

-- Walks MUTATOR_CATALOG and returns a flat list of mutator names
-- whose individual checkboxes are on. DLC-gated mutators owned by the
-- host pass; un-owned ones are dropped so they never reach the lobby.
local function selected_individual_mutators()
    local out = {}
    for ci = 1, #MUTATOR_CATALOG do
        local cat = MUTATOR_CATALOG[ci]
        for mi = 1, #cat.mutators do
            local id = cat.mutators[mi]
            if mod:get("mut_" .. id) and mutator_allowed(id) then
                out[#out + 1] = id
            end
        end
    end
    return out
end

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
        -- (suppress on with no injection of our own).
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
    local n = 0
    for ci = 1, #MUTATOR_CATALOG do
        local cat = MUTATOR_CATALOG[ci]
        for mi = 1, #cat.mutators do
            local id = cat.mutators[mi]
            if mod:get("mut_" .. id) then
                mod:set("mut_" .. id, false, false)
                n = n + 1
            end
        end
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
