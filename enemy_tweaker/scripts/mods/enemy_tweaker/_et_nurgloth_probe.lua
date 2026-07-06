local mod = get_mod("enemy_tweaker")

-- ============================================================================
-- Nurgloth phase-desync blackboard probe (issue 275 diagnostics)
-- ============================================================================
-- Issue #275: Nurgloth the Eternal (breed `chaos_exalted_sorcerer_drachenfels`,
-- The Enchanter's Lair = `dlc_castle`) desyncs into his final phase the moment
-- he appears, with health floored at ~66% on a friend's machine. gut's cutscene
-- skip was exonerated (cinematic played fully; desync persisted). We need
-- host-side blackboard state captured on the next repro to see WHY the fight
-- jumps a phase at spawn.
--
-- 66% is exactly the two-thirds phase-transition threshold: the drachenfels
-- behaviour tree flips to the next phase when `blackboard.current_health_percent
-- <= 0.66 and not blackboard.two_thirds_transition_done`
-- (bt_conditions.lua:332), and `<= 0.33` for the one-third transition
-- (bt_conditions.lua:324). So the STATE line below reads that exact FIELD
-- (`blackboard.current_health_percent`, the value the BT tests) alongside the
-- transition-done flags and mode/phase, and the SPAWN line reads the health
-- EXTENSION's own percent (`health_extension:current_health_percent()`,
-- generic_health_extension.lua:183) so a divergence between the two is visible.
--
-- Vanilla source (all under C:\Users\danjo\source\repos\Vermintide-2-Source-Code):
--   scripts/settings/dlcs/penny/penny_ai_breed_snippets.lua
--     :48  on_chaos_exalted_sorcerer_drachenfels_spawn (sets in_boss_arena,
--          mode="setup"/intro_timer OR phase="offensive", health_extension,
--          defensive_phase_duration)
--     :286 on_chaos_exalted_sorcerer_drachenfels_update
--   scripts/settings/dlcs/penny/penny_ai_settings_part_3.lua
--     :155 set_min_health_percentage(0.32) gate on the transition flags
--     :222/:225 two_thirds/one_third_transition_done set true
--     :245 third_phase_in_progress set true
--   scripts/unit_extensions/generic/generic_health_extension.lua
--     :183 current_health_percent()  :199 set_min_health_percentage (stores
--          self._min_health_percentage -- the field this probe reads)
--
-- HOOK PRE-FLIGHT (repo NON-NEGOTIABLE #8): grepped ALL of enemy_tweaker for
-- existing hooks on (AiBreedSnippets, on_chaos_exalted_sorcerer_drachenfels_spawn)
-- and (..._update). NONE exist -- these two mod:hook_safe are NEW, no merge.
--
-- CROSS-MOD (issue #275): the friend also runs DutchSpice, which
-- `mod.hook_origin(mod, AiBreedSnippets, "on_chaos_exalted_sorcerer_drachenfels_spawn", ...)`
-- (DutchSpice.lua:1766) -- a faithful field-wise REPLACEMENT of the spawn body.
-- VMF's duplicate-hook drop is per-mod (hooks.lua _registry[mod][unique_id]), so
-- a hook_safe on the same target from a DIFFERENT mod is fine. String-form
-- "AiBreedSnippets" resolves via rawget(_G,...) to the SAME table DutchSpice
-- passes (hooks.lua get_object_reference:46), so we share one internal
-- dispatcher; safe hooks run AFTER the hook chain -- including a hook_origin
-- replacement -- receiving the original args (hooks.lua create_internal_hook
-- :160-166). So this probe fires even when DutchSpice's replacement is active.
--
-- Diagnostics doctrine: always-on in dev, NO menu toggle (repo rule). Engine
-- `printf` (the user plays with VMF mod-logging OFF, so mod:info/debug never
-- reach the handed-over console log; printf always lands in console-*.log).
-- Every read is guarded (the extension can be mid-init in the replaced path)
-- and the whole body is pcall-wrapped so a probe fault can never break the
-- fight -- the error is printf'd once per boss.

local STATE_THROTTLE = 5  -- seconds between throttled STATE lines (per boss)
local HP_UNAVAILABLE = -1 -- %.3f sentinel when a health percent can't be read

-- _p275(fmt, ...) -- direct engine printf, pcall-guarded like the mod's other
-- printf helpers (_dbg_alert / _spawn_dbg_alert). No rate-limit here; the
-- callers below own their throttling (SPAWN is one-shot, STATE is 5s + on-change).
local function _p275(fmt, ...)
    if not pcall(printf, fmt, ...) then
        pcall(printf, "[et:275] (probe format error)")
    end
end

-- Read an extension member as a display string; "nil" if the extension isn't a
-- table yet (mid-init in the DutchSpice-replaced path).
local function _he_field(he, field)
    if type(he) ~= "table" then return "nil" end
    return tostring(he[field])
end

-- Call health_extension:current_health_percent() defensively; sentinel on any
-- failure so the %.3f format always gets a number.
local function _ext_hp_pct(he)
    if type(he) ~= "table" then return HP_UNAVAILABLE end
    local f = he.current_health_percent
    if type(f) ~= "function" then return HP_UNAVAILABLE end
    local ok, v = pcall(f, he)
    if ok and type(v) == "number" then return v end
    return HP_UNAVAILABLE
end

-- Coerce a possibly-nil blackboard number field for a %.3f slot.
local function _numf(v)
    if type(v) == "number" then return v end
    return HP_UNAVAILABLE
end

-- ----------------------------------------------------------------------------
-- SPAWN: one line, unconditional (one-shot per boss spawn).
-- ----------------------------------------------------------------------------
local _spawn_err_logged = false
mod:hook_safe("AiBreedSnippets", "on_chaos_exalted_sorcerer_drachenfels_spawn", function(unit, blackboard)
    local ok, err = pcall(function()
        if type(blackboard) ~= "table" then
            _p275("[et:275] SPAWN | blackboard=nil (unit=%s)", tostring(unit))
            return
        end
        local he = blackboard.health_extension
        _p275("[et:275] SPAWN | in_boss_arena=%s mode=%s phase=%s intro_timer=%s hp_pct=%.3f min_hp_pct=%s invincible=%s",
            tostring(blackboard.in_boss_arena),
            tostring(blackboard.mode),
            tostring(blackboard.phase),
            tostring(blackboard.intro_timer),
            _ext_hp_pct(he),
            _he_field(he, "_min_health_percentage"),
            _he_field(he, "is_invincible"))
    end)
    if not ok and not _spawn_err_logged then
        _spawn_err_logged = true
        pcall(printf, "[et:275] SPAWN probe error (once): %s", tostring(err))
    end
end)

-- ----------------------------------------------------------------------------
-- UPDATE: throttled to one line / STATE_THROTTLE seconds, PLUS an immediate
-- line whenever mode / phase / two_thirds / one_third changes since last print.
-- Throttle + last-seen state live on the blackboard (auto-freed on despawn).
-- ----------------------------------------------------------------------------
mod:hook_safe("AiBreedSnippets", "on_chaos_exalted_sorcerer_drachenfels_update", function(unit, blackboard, t, dt)
    local ok, err = pcall(function()
        if type(blackboard) ~= "table" then return end

        local mode       = blackboard.mode
        local phase      = blackboard.phase
        local two_thirds = blackboard.two_thirds_transition_done
        local one_third  = blackboard.one_third_transition_done

        local changed =
            mode ~= blackboard._et275_last_mode
            or phase ~= blackboard._et275_last_phase
            or two_thirds ~= blackboard._et275_last_two_thirds
            or one_third ~= blackboard._et275_last_one_third

        local now = (type(t) == "number") and t or 0
        local due = (blackboard._et275_next_print == nil) or (now >= blackboard._et275_next_print)

        if changed or due then
            local he = blackboard.health_extension
            _p275("[et:275] STATE t=%.1f | mode=%s phase=%s hp_pct=%.3f min_hp_pct=%s invincible=%s two_thirds_done=%s one_third_done=%s third_phase=%s defensive_dur=%s",
                now,
                tostring(mode),
                tostring(phase),
                _numf(blackboard.current_health_percent),
                _he_field(he, "_min_health_percentage"),
                _he_field(he, "is_invincible"),
                tostring(two_thirds),
                tostring(one_third),
                tostring(blackboard.third_phase_in_progress),
                tostring(blackboard.defensive_phase_duration))

            blackboard._et275_next_print       = now + STATE_THROTTLE
            blackboard._et275_last_mode        = mode
            blackboard._et275_last_phase       = phase
            blackboard._et275_last_two_thirds  = two_thirds
            blackboard._et275_last_one_third   = one_third
        end
    end)
    if not ok and type(blackboard) == "table" and not blackboard._et275_err_logged then
        blackboard._et275_err_logged = true
        pcall(printf, "[et:275] STATE probe error (once): %s", tostring(err))
    end
end)

mod:info("[et:275] Nurgloth blackboard phase probe armed (spawn + update)")
