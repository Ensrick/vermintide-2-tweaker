local mod = get_mod("event_tweaker")

-- _evt_diagnostics.lua — diagnostic chat commands + issue 393 snapshot probe
--
-- Read-only surfaces for verifying what the mod is (or would be) injecting:
-- /event_probe, /event_active, /event_clear, and the issue 393
-- diagnostics-armed first-Pacing-update settled snapshot. No behavior
-- changes live here; everything is echo/printf output plus the /event_clear
-- checkbox reset.
--
-- Owned by: event_tweaker.lua entry point (dofile'd after _evt_selection).
-- Consumes mod._evt: gather_mutators, suppress_live_event,
-- displayable_registered_mutators; requires the shared catalog/curses modules
-- for /event_clear's sweep.

local ET = mod._evt

local Catalog         = require("scripts/mods/event_tweaker/event_tweaker_catalog")
local MUTATOR_CATALOG = Catalog.CATEGORIES
local Curses          = require("scripts/mods/event_tweaker/event_tweaker_curses")
local MANAGED_CURSES  = Curses.MANAGED_CURSES
local Issue393        = require("scripts/mods/event_tweaker/_evt_issue393_probe")

local gather_mutators                = ET.gather_mutators
local suppress_live_event            = ET.suppress_live_event
local displayable_registered_mutators = ET.displayable_registered_mutators

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
-- Post-init conflict-settings snapshot (issue 393 diagnostics-armed)
-- ============================================================
-- Issue 386 (v0.4.22-dev) stopped the injected high_intensity mutator from
-- CRASHING ConflictDirector.init, but the mutator reportedly has little
-- observable in-mission effect. Hypothesis [unverified]: enemy_tweaker's own
-- conflict-director patch re-application runs on the SAME
-- refresh_conflict_director_patches chain (conflict_director.lua:886, dispatched
-- from ConflictDirector.init line 94) and overwrites the mutator's
-- CurrentIntensitySettings / CurrentPacing writes (mutator_high_intensity.lua:8-14
-- sets max_intensity=200, decay_per_second=10, decay_delay=0.5,
-- intensity_add_per_percent_dmg_taken=0.1, and the three delay_*_threat_value=200)
-- AFTER they land but before they take effect.
--
-- A ConflictDirector.init post-hook is not a reliable "final" boundary when
-- another mod wraps init and mutates settings after its inner call returns.
-- Instead, sample after the first Pacing.update: every init wrapper has returned
-- by then and the mission is consuming the resolved state. Print ONE line per
-- Pacing instance, snapshotting the four CurrentIntensitySettings fields
-- the mutator writes, the three CurrentPacing.delay_*_threat_value fields
-- (post-#386 sanitizer these are per-difficulty tables, summarized as
-- table:normal=<v>), and the converted self.delay_horde_threat_value the director
-- instance will actually pace against (conflict_director.lua:219). The injected
-- list is event_tweaker's own gather_mutators() -- the same builder the
-- [event-inject] special_events line uses.
--
-- What the line proves either way:
--   * injected list contains high_intensity but max_intensity reads a vanilla
--     default (not 200) and/or the delays are NOT table:normal=200 -> the
--     mutator's writes were STOMPED after landing (confirms the hypothesis;
--     next step is ordering enemy_tweaker's re-application vs the mutator).
--   * max_intensity=200 and delays table:normal=200 with high_intensity injected
--     -> the writes SURVIVED intact, so the "little effect" report is not a
--     stomped-settings problem and the search moves to how the pacing/intensity
--     values are consumed (or to a difficulty-scaling / perception issue).
-- The classifier explicitly reports `settings_stomp` vs `intact`; an intact
-- result is evidence that the remaining report is about vanilla semantics, not
-- hook ordering. Source audit: GenericStatusExtension hard-caps player pacing
-- intensity at 100, so the mutator's max_intensity=200 cannot itself raise the
-- observed intensity ceiling; its effect is indirect (decay/damage gain and the
-- director delay thresholds).
-- printf only (user logs OFF); guarded; one cheap line per mission, always on in
-- dev per the diagnostics doctrine. No behavior change.
local _issue393_seen = setmetatable({}, { __mode = "k" })
mod:hook_safe("Pacing", "update", function(self)
    if _issue393_seen[self] then return end
    _issue393_seen[self] = true
    pcall(function()
        local cis = rawget(_G, "CurrentIntensitySettings")
        local cp  = rawget(_G, "CurrentPacing")
        -- Pacing delay fields are per-difficulty tables after the #386 sanitizer
        -- (or in vanilla base form); a raw scalar means an un-sanitized write.
        local function _pac(v)
            if type(v) == "table" then return "table:normal=" .. tostring(v.normal) end
            return tostring(v)
        end
        local injected = gather_mutators()
        local cd = rawget(_G, "Managers") and Managers.state and Managers.state.conflict
        local cached = {
            delay_horde_threat_value = cd and cd.delay_horde_threat_value,
            delay_specials_threat_value = cd and cd.delay_specials_threat_value,
            delay_mini_patrol_threat_value = cd and cd.delay_mini_patrol_threat_value,
        }
        local verdict, evidence = Issue393.classify(injected, cis, cp, cached)
        if verdict == "not_injected" then return end
        local inj_str = (injected and #injected > 0) and table.concat(injected, ",") or "none"
        printf("[event-inject:393] settled verdict=%s evidence=%s | injected=[%s] max_intensity=%s decay_per_second=%s decay_delay=%s add_per_pct_dmg=%s delay_horde=%s delay_specials=%s delay_mini_patrol=%s cached_horde=%s cached_specials=%s cached_mini_patrol=%s",
            tostring(verdict), tostring(evidence),
            inj_str,
            tostring(cis and cis.max_intensity),
            tostring(cis and cis.decay_per_second),
            tostring(cis and cis.decay_delay),
            tostring(cis and cis.intensity_add_per_percent_dmg_taken),
            _pac(cp and cp.delay_horde_threat_value),
            _pac(cp and cp.delay_specials_threat_value),
            _pac(cp and cp.delay_mini_patrol_threat_value),
            tostring(cached.delay_horde_threat_value),
            tostring(cached.delay_specials_threat_value),
            tostring(cached.delay_mini_patrol_threat_value))
    end)
end)

ET.rt_register("issue393_high_intensity_settled_classifier", function()
    local injected = { "high_intensity" }
    local cis = {
        max_intensity = 200, decay_per_second = 10, decay_delay = 0.5,
        intensity_add_per_percent_dmg_taken = 0.1,
    }
    local cp = {
        delay_horde_threat_value = { normal = 200 },
        delay_specials_threat_value = { normal = 200 },
        delay_mini_patrol_threat_value = { normal = 200 },
    }
    local cached = {
        delay_horde_threat_value = 200,
        delay_specials_threat_value = 200,
        delay_mini_patrol_threat_value = 200,
    }
    local verdict = Issue393.classify(injected, cis, cp, cached)
    if verdict ~= "intact" then return "canonical mutator state did not classify intact" end
    cis.max_intensity = 100
    verdict = Issue393.classify(injected, cis, cp, cached)
    if verdict ~= "settings_stomp" then return "intensity overwrite was not detected" end
    cis.max_intensity = 200
    cached.delay_horde_threat_value = 75
    verdict = Issue393.classify(injected, cis, cp, cached)
    if verdict ~= "settings_stomp" then return "cached director overwrite was not detected" end
end)
