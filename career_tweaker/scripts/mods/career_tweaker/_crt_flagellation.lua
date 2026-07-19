-- _crt_flagellation.lua - Zealot Devotion replacement for issue #447.
--
-- Resolves the live Devotion talent by localizing each candidate's vanilla
-- title key (display_name or name, hero_window_talents.lua:328), scopes
-- conversion to the native level-5 THP proc call windows, and converts green
-- health equal to half the realized THP gain. No buff name, RPC, or
-- NetworkLookup entry is added.
--
-- Owned by: career_tweaker.lua entry point. Consumed via: mod:dofile.

local mod = get_mod("crt")
mod._crt = mod._crt or {}
local policy = mod:dofile("scripts/mods/career_tweaker/_crt_flagellation_policy")
mod._crt.flagellation = { policy = policy, proc_names = {}, devotion = nil }
local state = mod._crt.flagellation

local function zealot_candidates()
    local result = {}
    local lookup = rawget(_G, "TalentIDLookup") or {}
    local talents = rawget(_G, "Talents") or {}
    for name, row in pairs(lookup) do
        if type(name) == "string" and name:find("^victor_zealot_") == 1 then
            local talent = talents[row.hero_name] and talents[row.hero_name][row.talent_id]
            if talent then
                result[#result + 1] = {
                    name = name,
                    -- Vanilla resolves a talent title via
                    -- Localize(display_name or name) (hero_window_talents.lua:328).
                    -- Only the three thp_* talents carry display_name
                    -- (talent_settings_victor.lua:1408/1420/1432); for the other
                    -- 18 the internal name IS the title loc key. Localizing only
                    -- display_name is what kept #447 inert (all keys nil).
                    display_key = talent.display_name or name,
                    description = talent.description,
                    buffs = talent.buffs,
                }
            end
        end
    end
    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end

local diagnostic_count = 0
local function evidence(fmt, ...)
    if diagnostic_count >= 32 then return end
    diagnostic_count = diagnostic_count + 1
    pcall(printf, "[crt:447] " .. fmt, ...)
end

local function register_overrides(devotion)
    mod._crt.extra_desc_overrides = mod._crt.extra_desc_overrides or {}
    if devotion.display_key then
        mod._crt.extra_desc_overrides[devotion.display_key] = {
            setting = "rework_wh_zealot_flagellation",
            text = "Flagellation",
        }
    end
    if devotion.description then
        mod._crt.extra_desc_overrides[devotion.description] = {
            setting = "rework_wh_zealot_flagellation",
            text = "Gaining temporary health from your level 5 talent also converts permanent health equal to half the temporary health gained.",
        }
    end
end

-- Resolve Devotion from the live talent table + raw loc data. Idempotent; the
-- consolidated Localize hook retries once at first menu localization if file
-- load was inconclusive (state.lazy_retry_pending). Clears the retry flag
-- FIRST so the Localize calls inside cannot re-enter this function.
state.lazy_retry_pending = false
function state.try_resolve()
    state.lazy_retry_pending = false
    if state.devotion then return state.devotion end
    local devotion, census = policy.resolve_devotion(zealot_candidates(),
        function(key) return Localize(key) end)
    state.census = census
    evidence("census candidates=%d resolved=%d unresolved=%d matches=%d",
        census.candidates, census.resolved, census.unresolved, census.matches)
    if devotion then
        state.devotion = devotion
        register_overrides(devotion)
        evidence("resolved Devotion internal=%s display_key=%s title=%s",
            devotion.name, tostring(devotion.display_key), tostring(devotion.title))
    else
        evidence("Devotion unresolved candidates=%d; feature inert", census.candidates)
        for i = 1, math.min(#census.rows, 12) do
            local row = census.rows[i]
            evidence("candidate name=%s display_key=%s title=%s", tostring(row.name),
                tostring(row.display_key), tostring(row.title or "<loc-error>"))
        end
    end
    return state.devotion
end

state.try_resolve()
if not state.devotion then
    state.lazy_retry_pending = true
end

local proc_context = setmetatable({}, { __mode = "k" })
local function flagellation_selected(unit)
    if not mod:get("rework_wh_zealot_flagellation") or not state.devotion then return false end
    local talents = ScriptUnit.has_extension(unit, "talent_system")
    return talents and talents._career_name == "wh_zealot"
        and talents:has_talent(state.devotion.name)
end

local function collect_level5_procs()
    local names = {}
    for _, talent_name in ipairs({
        "victor_zealot_thp_linesman", "victor_zealot_thp_smiter", "victor_zealot_thp_tank",
    }) do
        local lookup = TalentIDLookup and TalentIDLookup[talent_name]
        local talent = lookup and Talents[lookup.hero_name] and Talents[lookup.hero_name][lookup.talent_id]
        for _, buff_name in ipairs(talent and talent.buffs or {}) do
            local parent = BuffTemplates and BuffTemplates[buff_name]
            for _, sub in ipairs(parent and parent.buffs or {}) do
                if type(sub.buff_func) == "string" then names[sub.buff_func] = true end
            end
        end
    end
    return names
end

local proc_functions = rawget(_G, "ProcFunctions")
for proc_name in pairs(collect_level5_procs()) do
    local original = proc_functions and proc_functions[proc_name]
    if type(original) == "function" then
        state.proc_names[#state.proc_names + 1] = proc_name
        proc_functions[proc_name] = function(unit, ...)
            local active = flagellation_selected(unit)
            if active then proc_context[unit] = (proc_context[unit] or 0) + 1 end
            local ok, a, b, c, d = pcall(original, unit, ...)
            if active then
                local depth = (proc_context[unit] or 1) - 1
                proc_context[unit] = depth > 0 and depth or nil
            end
            if not ok then error(a, 0) end
            return a, b, c, d
        end
    end
end
table.sort(state.proc_names)

mod:hook("PlayerUnitHealthExtension", "add_heal", function(func, self,
        healer_unit, heal_amount, heal_source_name, heal_type)
    local unit = self.unit
    local active = self.is_server and unit and (proc_context[unit] or 0) > 0
    local before = active and self:current_temporary_health() or 0
    func(self, healer_unit, heal_amount, heal_source_name, heal_type)
    if not active then return end
    local after = self:current_temporary_health()
    local permanent = self:current_permanent_health()
    local amount, gained = policy.conversion_amount(before, after, permanent)
    if amount > 0 then
        self:convert_to_temp(amount)
        evidence("converted=%.2f realized_thp=%.2f permanent_before=%.2f",
            amount, gained, permanent)
    end
end)

state.hook_installed = true
