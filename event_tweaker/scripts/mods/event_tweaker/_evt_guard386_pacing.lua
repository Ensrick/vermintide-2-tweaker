local mod = get_mod("event_tweaker")

-- _evt_guard386_pacing.lua — issue 386: injected-mutator conflict-settings sanitizer
--
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
-- Fix (shipped v0.4.22-dev; DO NOT REMOVE): a hook_safe on
-- conflict_director_updated_settings runs AFTER the vanilla body writes the
-- scalars, still synchronously inside refresh_conflict_director_patches, so
-- BEFORE init's line 219 read. It converts any scalar left in those three
-- fields into a per-difficulty table. get_value_for_difficulty walks DOWN the
-- Difficulties list to index 1 == "normal", so keying the floor difficulty covers
-- EVERY difficulty; the resolved current difficulty is stamped too for clarity.
-- init then reads a table and resolves the intended magnitude (200) with no crash.
-- Host-only in effect (conflict_director_updated_settings early-returns on clients),
-- and a strict no-op whenever the fields are already tables -- i.e. whenever we
-- inject nothing, or on any pass after the first, the scan finds no scalar.
-- Regression check issue386_sanitize_pacing_scalar_to_table.
--
-- If you add a mutator to the catalog: if its source update_conflict_settings
-- assigns a plain number to any field ConflictDirector reads as a per-difficulty
-- table, extend PACING_TABLE_FIELDS if a new field surfaces.
--
-- Owned by: event_tweaker.lua entry point. Exposes
-- mod._et386_sanitize_pacing_scalars for the regression check / siblings.

local ET = mod._evt
local rt_register = ET.rt_register

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

rt_register("issue386_sanitize_pacing_scalar_to_table", function()
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
