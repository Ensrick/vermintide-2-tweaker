local mod = get_mod("event_tweaker")

-- _evt_selection.lua — mutator/preset selection accumulators
--
-- Owns everything that decides WHAT the mod injects: the active-preset
-- resolver, dynamic mutator discovery (the Deed Mutators Selector port), the
-- curse/checkbox selection readers, and the gather_mutators() /
-- gather_active_events() builders the backend hooks consume. gather's add()
-- is the single injection chokepoint every route funnels through (preset,
-- checkbox, discovered, curse) — the issue 413 weave gate and issue 455
-- boss-event guard are applied there and must not be bypassed by any new
-- injection route. The issue 430 curse wire-safety floor lives one step earlier
-- in selected_curse_mutators() (it removes curses from the route rather than
-- adding one, so no guard is bypassed): the package-bearing Cursed Adventure
-- curses are dropped entirely whenever a lobby peer lacks event_tweaker, because
-- a non-ET peer CTDs on the curse's replicated husk from an unloaded package
-- (see _evt_guard430_curse_parity.lua).
--
-- Owned by: event_tweaker.lua entry point (dofile'd after _evt_dlc +
-- _evt_guard413_weave + _evt_guard455_boss_events, before the hook/command
-- modules). Consumed via mod._evt exports: active_preset, gather_mutators,
-- preview_selection (issue 532 Tab preview), gather_active_events,
-- suppress_live_event, merge_lists, displayable_registered_mutators.

local ET = mod._evt
local rt_register = ET.rt_register

-- Shared require'd catalogs (also read by _data.lua / _localization.lua —
-- see event_tweaker_catalog.lua / event_tweaker_curses.lua headers for why
-- these are require'd modules, not mod._fields).
local Catalog         = require("scripts/mods/event_tweaker/event_tweaker_catalog")
local MUTATOR_CATALOG = Catalog.CATEGORIES
local EVENT_PRESETS   = Catalog.EVENT_PRESETS

-- Cursed Adventure — Chaos Wastes / Be'lakor curse catalog (verified by
-- adversarial source audit 2026-06-19 — see DEVELOPMENT.md "Cursed Adventure"
-- + CHANGELOG 0.4.14-dev). These curses normally run only inside the Chaos
-- Wastes / Deus realm because their unit/decal resource PACKAGE is loaded only
-- by DeusRunState.set_event_mutators (deus_run_state.lua:438-453); the
-- mechanics themselves use only standard mission managers and every DLC entity
-- system is registered into EVERY mission at boot (entity_system.lua:176 +
-- :424-435). So once _evt_cursed_adventure.lua preloads the package on every
-- peer, they run on a plain adventure map. NB: clients ALSO need the package
-- (spawn_network_unit replicates a husk), so unlike the host-only "Other
-- Mutators" group, the Cursed Adventure group requires event_tweaker on EVERY peer.
local Curses                     = require("scripts/mods/event_tweaker/event_tweaker_curses")
local MANAGED_CURSES             = Curses.MANAGED_CURSES
local _CURSE_BROKEN_IN_ADVENTURE = Curses.BROKEN_IN_ADVENTURE

-- Earlier-module exports, localized once at load (manifest order guarantees
-- they exist).
local owns_dlc            = ET.owns_dlc
local mutator_allowed     = ET.mutator_allowed
local preset_allowed      = ET.preset_allowed
local WEAVE_ONLY_MUTATORS = ET.WEAVE_ONLY_MUTATORS
local _weave_wind_active  = ET.weave_wind_active
local notify_weave_drop   = ET.notify_weave_drop
-- issue 430 curse wire-safety floor (manifest order: _evt_guard430_curse_parity
-- is dofile'd before this module, so the export exists here).
local curse_wire_safe     = ET.curse_wire_safe

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
-- display_name and a description). MUTATOR_CATALOG is a curated,
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
--      preloads the package first (see _evt_cursed_adventure.lua).
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
-- trigger per-peer package preload + cursed-sky lighting (_evt_cursed_adventure.lua).
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
    -- issue 430: UNCONDITIONAL sender-side crash floor. These curses spawn
    -- network-replicated husks from a resource package that ONLY peers running
    -- event_tweaker preload (_evt_cursed_adventure.lua). A non-ET peer that
    -- receives the curse activation via rpc_activate_mutator_client hard-CTDs on
    -- the husk spawn from the unloaded package. Gameplay axis -> substitution is
    -- not applicable (issue 371 / BUG_CLASSES 31); the only floor is to DECLINE
    -- injection while any lobby peer is unconfirmed (issue 413 lesson). The
    -- checkbox being on is necessary but this parity check is a hard AND the user
    -- cannot override (never toggle-gated). curse_wire_safe() is positive-evidence
    -- + fail-safe (false when the beacon is missing/erroring or any peer is
    -- unacked), read live so a peer joining just before the mission still blocks.
    -- The beacon (_evt_guard430_curse_parity) chat-notifies which peer lacks the
    -- mod; this printf is the log-only trail, mirroring the issue 413 drop.
    if #out > 0 and not (curse_wire_safe and curse_wire_safe()) then
        pcall(printf, "[et:430] dropped %d Cursed Adventure curse(s): a lobby peer lacks event_tweaker (would CTD on the curse husk from an unloaded package)", #out)
        return {}
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

rt_register("dynamic_mutator_discovery", function()
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
        -- issue 413: outside a real weave, weave-only mutators must never
        -- reach append_live_event_mutators -- the engine broadcasts each
        -- name to every peer via rpc_activate_mutator_client, and the
        -- payload crashes clients (shadow: non-resident unit + Unit.light
        -- engine fatal) or the host (heavens/light/death/beasts: nil
        -- wind_settings index). Single chokepoint: every injection route
        -- (preset, checkbox, discovered, curse) funnels through here.
        if WEAVE_ONLY_MUTATORS[name] and not _weave_wind_active() then
            pcall(printf, "[et:413] dropped weave-only mutator [" .. tostring(name)
                .. "] (no active wind settings - not a Weave mission)")
            -- issue 413 follow-up: if the HOST explicitly ticked this Winds box,
            -- surface a one-line reason (the printf above is console-only and
            -- invisible with mod-logging off). Preset-injected drops stay silent.
            if notify_weave_drop and mod:get("mut_" .. name) then
                notify_weave_drop(name)
            end
            return
        end
        -- issue 455: mutators that index CurrentBossSettings.boss_events
        -- unguarded get their dispatch fields wrapped (once) so fixed-boss
        -- levels like warcamp no-op instead of a host fatal.
        mod._et455_guard_boss_event_mutator(name)
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

-- issue 532: the mutator selection this lobby WOULD inject, split into what
-- actually activates and what the issue 430 curse-parity floor drops. Consumed by
-- the Tab-hold preview (_evt_preview.lua) + /event_preview_mutators. Side-effect
-- free: it mirrors gather_mutators()'s weave gate WITHOUT that path's chat notice
-- (notify_weave_drop) or template mutation (_et455_guard_boss_event_mutator), so
-- opening the panel every frame's-worth of times cannot spam chat or re-wrap
-- dispatch fields. Returns two tables:
--   active  = ordered { name, is_curse } that will reach append_live_event_mutators
--             (preset + individual + floor-passing curses, deduped; weave-only
--             names dropped outside a real Weave exactly as gather_mutators drops
--             them -- so the preview never advertises a mutator that won't activate).
--   dropped = curse names the parity floor removes (checkbox on + DLC owned +
--             registered, but a lobby peer lacks event_tweaker). The panel renders
--             these greyed/flagged so a curse that will NOT activate is never
--             advertised as active.
local function preview_selection()
    local seen, active = {}, {}
    local function consider(name, is_curse)
        if WEAVE_ONLY_MUTATORS[name] and not _weave_wind_active() then
            return  -- same drop gather_mutators applies; minus its chat notice
        end
        if not seen[name] then
            seen[name] = true
            active[#active + 1] = { name = name, is_curse = is_curse or false }
        end
    end

    local preset = active_preset()
    if preset and preset.mutators then
        for i = 1, #preset.mutators do
            if mutator_allowed(preset.mutators[i]) then
                consider(preset.mutators[i], false)
            end
        end
    end

    local individual = selected_individual_mutators()
    for i = 1, #individual do
        consider(individual[i], false)
    end

    -- selected_curse_mutators() already applies the issue 430 floor (returns {}
    -- when a peer lacks the mod), so anything it hands back genuinely activates.
    local curses = selected_curse_mutators()
    for i = 1, #curses do
        consider(curses[i], true)
    end

    -- Floor-dropped curses: the user checked them and owns the DLC, but the
    -- parity floor removed them (a lobby peer lacks event_tweaker). Enumerated
    -- separately so the panel can list them greyed instead of silently vanishing.
    local dropped = {}
    if not (curse_wire_safe and curse_wire_safe()) then
        local MT = rawget(_G, "MutatorTemplates")
        for i = 1, #MANAGED_CURSES do
            local c = MANAGED_CURSES[i]
            if mod:get("mut_" .. c.id) and owns_dlc(c.dlc)
               and (not MT or rawget(MT, c.id)) then
                dropped[#dropped + 1] = c.id
            end
        end
    end

    return active, dropped
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

ET.active_preset = active_preset
ET.displayable_registered_mutators = displayable_registered_mutators
ET.gather_mutators = gather_mutators
ET.preview_selection = preview_selection
ET.gather_active_events = gather_active_events
ET.suppress_live_event = suppress_live_event
ET.merge_lists = merge_lists
