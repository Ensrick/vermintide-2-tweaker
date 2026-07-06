local mod = get_mod("enemy_tweaker")

-- ============================================================================
-- Nurgloth phase-desync probe (issue 275 diagnostics) -- breed-field wrap rewrite
-- ============================================================================
-- Issue #275: Nurgloth the Eternal (breed `chaos_exalted_sorcerer_drachenfels`,
-- The Enchanter's Lair) desyncs into his final phase the moment he appears, with
-- health floored at ~66% on a friend's machine. gut's cutscene skip was
-- exonerated (cinematic played fully; desync persisted). We need host-side
-- blackboard state captured on the next repro to see WHY the fight jumps a phase
-- at spawn.
--
-- WHY THE FIRST PROBE NO-OPED (v0.7.29-dev): it hooked the `AiBreedSnippets`
-- TABLE via `mod:hook_safe`. Vanilla never calls the snippet through that table
-- at runtime -- the breed captures a DIRECT function reference at breed-definition
-- load: `run_on_spawn = AiBreedSnippets.on_chaos_exalted_sorcerer_drachenfels_spawn`
-- (breed_chaos_exalted_sorcerer_drachenfels.lua:119) and the engine invokes
-- `breed.run_on_spawn(unit, blackboard)` (ai_simple_extension.lua:227 and :257 --
-- TWO call sites, so the SPAWN line below prints twice per boss). A table hook on
-- `AiBreedSnippets` never fires. Tonight's author log confirmed it: probe armed at
-- load, ZERO SPAWN/STATE lines across a full boss fight.
--
-- THE FIX: wrap the BREED TABLE FIELDS directly (pure field wrap, no mod:hook on
-- the snippet -- mirrors et's _et_boss_tweaks.lua data-mutation style):
--   * `breed.run_on_spawn`       -> invoked at ai_simple_extension.lua:227/:257
--   * `breed.run_on_game_update` -> invoked at ai_system.lua:894 (fresh table
--     lookup every frame; NOTE the field is `run_on_game_update`, not
--     `run_on_update`; breed_chaos_exalted_sorcerer_drachenfels.lua:120)
-- The wrapper calls the exact original reference the field held (raw, so vanilla
-- behavior is byte-for-byte preserved), then runs the pcall-guarded probe AFTER
-- so the blackboard is fully populated. Whatever reference the field holds is the
-- function the engine actually runs, so the probe fires on the real spawn/update
-- path regardless of what any co-mod (e.g. DutchSpice) does to the AiBreedSnippets
-- table.
--
-- PHASE-TRANSITION TRACERS: the drachenfels behaviour tree resolves enter/leave
-- hooks BY NAME. The penny DLC registers them in `settings.bt_enter_hooks` /
-- `settings.bt_leave_hooks` (penny_ai_settings_part_3.lua:77 / :213); the engine
-- merges those into the global `BTEnterHooks` / `BTLeaveHooks` tables via
-- `DLCUtils.merge("bt_enter_hooks", BTEnterHooks)` (bt_enter_hooks.lua:542) and
-- `DLCUtils.merge("bt_leave_hooks", BTLeaveHooks)` (bt_leave_hooks.lua:339). We
-- wrap the seven merged drachenfels entries with a one-line tracer.
--
-- CRITICAL TIMING: `BTNode.init` captures the hook into an UPVALUE at node
-- construction and the enter/leave closure calls that captured value directly
-- (bt_node.lua:24-33). Node construction happens in `AISystem.create_all_trees`
-- (ai_system.lua:1693-1700), called from `AISystem.init` at mission load
-- (ai_system.lua:105). So a table-field wrap of BTEnterHooks/BTLeaveHooks only
-- takes effect if it is installed BEFORE the trees are parsed. We therefore drive
-- installation from a pre-step on `AISystem.create_all_trees` -- wrap the tables,
-- THEN call the original -- so every mission's freshly-built BTNodes capture our
-- wrappers. The breed-field wrap runs at the same point (Breeds is a boot global,
-- and mission load is well before the boss spawns). Both are idempotent across
-- missions (the wrappers persist on the tables; markers stop re-wrapping).
--
-- Vanilla source (all under C:\Users\danjo\source\repos\Vermintide-2-Source-Code):
--   scripts/settings/breeds/breed_chaos_exalted_sorcerer_drachenfels.lua
--     :119 run_on_spawn (direct AiBreedSnippets ref)  :120 run_on_game_update
--   scripts/unit_extensions/human/ai_player_unit/ai_simple_extension.lua
--     :227 / :257 breed.run_on_spawn(unit, blackboard)
--   scripts/entity_system/systems/ai/ai_system.lua
--     :894 breed.run_on_game_update(unit, blackboard, t, dt)
--     :1693 create_all_trees  :105 called from AISystem.init (mission load)
--   scripts/entity_system/systems/behaviour/nodes/bt_node.lua
--     :24-33 BTNode.init captures enter/leave hook as an upvalue
--   scripts/entity_system/systems/behaviour/nodes/bt_enter_hooks.lua
--     :542 DLCUtils.merge("bt_enter_hooks", BTEnterHooks)
--   scripts/entity_system/systems/behaviour/nodes/bt_leave_hooks.lua
--     :339 DLCUtils.merge("bt_leave_hooks", BTLeaveHooks)
--   scripts/settings/dlcs/penny/penny_ai_settings_part_3.lua
--     :77 bt_enter_hooks (intro_enter :78, begin_defensive :109, re_enter :133)
--     :213 bt_leave_hooks (intro_leave :260, two_thirds :221, one_third :224,
--          go_offensive_intense :233 sets third_phase_in_progress)
--   scripts/entity_system/systems/behaviour/nodes/bt_conditions.lua
--     :332 two-thirds flip: blackboard.current_health_percent <= 0.66
--     :324 one-third flip:  blackboard.current_health_percent <= 0.33
--   scripts/unit_extensions/generic/generic_health_extension.lua
--     :183 current_health_percent()  :199 set_min_health_percentage (stores
--          self._min_health_percentage -- the field this probe reads)
--
-- HOOK PRE-FLIGHT (repo NON-NEGOTIABLE #8): grepped ALL of enemy_tweaker for an
-- existing hook on (AISystem, create_all_trees) and (AISystem, init). NONE exist
-- -- the create_all_trees hook below is the sole registration on that pair.
--
-- Diagnostics doctrine: always-on in dev, NO menu toggle (repo rule). Engine
-- `printf` (the user plays with VMF mod-logging OFF, so mod:info/debug never reach
-- the handed-over console log; printf always lands in console-*.log). Every read
-- is guarded and the probe bodies are pcall-wrapped so a probe fault can never
-- break the fight -- the ORIGINAL always runs raw, so vanilla behavior is intact
-- even if the probe faults.

local STATE_THROTTLE = 5  -- seconds between throttled STATE lines (per boss)
local HP_UNAVAILABLE = -1 -- %.3f sentinel when a health percent can't be read

-- _p275(fmt, ...) -- direct engine printf, pcall-guarded like the mod's other
-- printf helpers (_dbg_alert / _spawn_dbg_alert). No rate-limit here; the callers
-- below own their throttling (SPAWN is one-shot, STATE is 5s + on-change).
local function _p275(fmt, ...)
    if not pcall(printf, fmt, ...) then
        pcall(printf, "[et:275] (probe format error)")
    end
end

-- Read an extension member as a display string; "nil" if the extension isn't a
-- table yet (mid-init in a replaced path).
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
-- SPAWN probe: one line, unconditional (fires per breed.run_on_spawn invocation
-- -- vanilla calls it twice per boss, so expect two SPAWN lines). Format is
-- UNCHANGED from v0.7.29-dev.
-- ----------------------------------------------------------------------------
local _spawn_err_logged = false
local function _probe_spawn(unit, blackboard)
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
end

-- ----------------------------------------------------------------------------
-- STATE probe: throttled to one line / STATE_THROTTLE seconds, PLUS an immediate
-- line whenever mode / phase / two_thirds / one_third changes since last print.
-- Throttle + last-seen state live on the blackboard (auto-freed on despawn).
-- Format is UNCHANGED from v0.7.29-dev.
-- ----------------------------------------------------------------------------
local function _probe_update(unit, blackboard, t, dt) -- luacheck: ignore unit dt
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
end

-- ----------------------------------------------------------------------------
-- HOOK tracer: one line whenever a wrapped BT enter/leave hook fires. Reads the
-- blackboard arg the hook received; all reads guarded. pcall-wrapped, once-per-
-- boss error latch so a tracer fault never disturbs the fight.
-- ----------------------------------------------------------------------------
local function _probe_hook(name, unit, blackboard, t) -- luacheck: ignore unit t
    local ok, err = pcall(function()
        local bb = (type(blackboard) == "table") and blackboard or nil
        local he = bb and bb.health_extension or nil
        _p275("[et:275] HOOK %s | hp_pct=%.3f min_hp_pct=%s two_thirds_done=%s one_third_done=%s",
            tostring(name),
            _numf(bb and bb.current_health_percent),
            _he_field(he, "_min_health_percentage"),
            tostring(bb and bb.two_thirds_transition_done),
            tostring(bb and bb.one_third_transition_done))
    end)
    if not ok and type(blackboard) == "table" and not blackboard._et275_hook_err_logged then
        blackboard._et275_hook_err_logged = true
        pcall(printf, "[et:275] HOOK probe error (once): %s", tostring(err))
    end
end

-- ----------------------------------------------------------------------------
-- Installation (idempotent). Wraps the breed fields and the BT enter/leave hooks.
-- Driven from the AISystem.create_all_trees pre-step below so it runs before the
-- BTNodes capture the hook upvalues.
-- ----------------------------------------------------------------------------

-- penny-registered drachenfels BT hooks (penny_ai_settings_part_3.lua).
local ENTER_HOOK_NAMES = {
    "on_chaos_exalted_sorcerer_drachenfels_intro_enter",  -- :78
    "sorcerer_drachenfels_re_enter_defensive_mode",       -- :133
    "sorcerer_drachenfels_begin_defensive_mode",          -- :109
}
local LEAVE_HOOK_NAMES = {
    "on_drachenfels_sorcerer_intro_leave",                -- :260
    "transition_at_two_thirds",                           -- :221 (sets two_thirds_transition_done)
    "transition_at_one_third",                            -- :224 (sets one_third_transition_done)
    "sorcerer_drachenfels_go_offensive_intense",          -- :233 (sets third_phase_in_progress)
}

-- Lua functions can't carry a marker field, so track wrapped BT hooks in a
-- module-level set keyed by "enter:<name>" / "leave:<name>". Persists across
-- missions; the registry entries persist too, so re-entry is a no-op.
local _bt_wrapped = {}
local _armed_logged = false
local _breed_logged = false

-- Wrap one BT hook registry entry: original first (so e.g. transition_at_two_thirds
-- has already set the flag), tracer after. Returns true if a NEW wrap was applied.
local function _wrap_bt(registry, name, kind)
    if type(registry) ~= "table" then return false end
    local key = kind .. ":" .. name
    if _bt_wrapped[key] then return false end
    local orig = registry[name]
    if type(orig) ~= "function" then return false end
    _bt_wrapped[key] = orig
    registry[name] = function(unit, blackboard, t)
        orig(unit, blackboard, t)                  -- raw: vanilla BT behavior preserved
        pcall(_probe_hook, name, unit, blackboard, t)
    end
    return true
end

local function _install_bt_tracers()
    local enter_reg = rawget(_G, "BTEnterHooks")
    local leave_reg = rawget(_G, "BTLeaveHooks")
    local n = 0
    for _, name in ipairs(ENTER_HOOK_NAMES) do
        if _wrap_bt(enter_reg, name, "enter") then n = n + 1 end
    end
    for _, name in ipairs(LEAVE_HOOK_NAMES) do
        if _wrap_bt(leave_reg, name, "leave") then n = n + 1 end
    end
    -- Total wrapped so far (across this + prior passes) = count of keys present.
    if not _armed_logged then
        local total = 0
        for _ in pairs(_bt_wrapped) do total = total + 1 end
        if total > 0 then
            _armed_logged = true
            _p275("[et:275] tracers armed: %d wrapped", total)
        end
    end
    return n
end

local function _install_breed_wrap()
    local breeds = rawget(_G, "Breeds")
    local breed = breeds and breeds.chaos_exalted_sorcerer_drachenfels
    if type(breed) ~= "table" then return end

    if not breed._et275_spawn_wrapped and type(breed.run_on_spawn) == "function" then
        local orig_spawn = breed.run_on_spawn
        breed.run_on_spawn = function(unit, blackboard)
            orig_spawn(unit, blackboard)           -- raw
            _probe_spawn(unit, blackboard)         -- probe body is self-pcall'd
        end
        breed._et275_spawn_wrapped = true
    end

    if not breed._et275_update_wrapped and type(breed.run_on_game_update) == "function" then
        local orig_update = breed.run_on_game_update
        breed.run_on_game_update = function(unit, blackboard, t, dt)
            orig_update(unit, blackboard, t, dt)   -- raw
            _probe_update(unit, blackboard, t, dt) -- probe body is self-pcall'd
        end
        breed._et275_update_wrapped = true
    end

    if not _breed_logged and breed._et275_spawn_wrapped and breed._et275_update_wrapped then
        _breed_logged = true
        _p275("[et:275] breed-field wrap installed (run_on_spawn + run_on_game_update)")
    end
end

local function _et275_install()
    _install_breed_wrap()
    _install_bt_tracers()
end

-- Drive installation before each mission's BTNodes capture the enter/leave hooks.
-- Pre-step wraps the tables, THEN the original create_all_trees parses the trees.
-- Sole enemy_tweaker hook on (AISystem, create_all_trees) -- see PRE-FLIGHT above.
mod:hook("AISystem", "create_all_trees", function(func, self)
    pcall(_et275_install)
    return func(self)
end)

mod:info("[et:275] Nurgloth probe loaded (breed-field wrap + BT phase tracers; installs at AISystem.create_all_trees)")
