-- _crt_flagellation.lua - Zealot Devotion replacement for issue #447.
--
-- Resolves the live Devotion talent, scopes conversion to the native level-5
-- THP proc call windows, and converts green health equal to half the realized
-- THP gain. No buff name, RPC, or NetworkLookup entry is added.
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
                    display_name = talent.display_name,
                    description = talent.description,
                    buffs = talent.buffs,
                }
            end
        end
    end
    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end

local candidates = zealot_candidates()
state.devotion = policy.resolve_devotion(candidates, function(key) return Localize(key) end)

local diagnostic_count = 0
local function evidence(fmt, ...)
    if diagnostic_count >= 32 then return end
    diagnostic_count = diagnostic_count + 1
    pcall(printf, "[crt:447] " .. fmt, ...)
end

if state.devotion then
    mod._crt.extra_desc_overrides = mod._crt.extra_desc_overrides or {}
    if state.devotion.display_name then
        mod._crt.extra_desc_overrides[state.devotion.display_name] = {
            setting = "rework_wh_zealot_flagellation",
            text = "Flagellation",
        }
    end
    if state.devotion.description then
        mod._crt.extra_desc_overrides[state.devotion.description] = {
            setting = "rework_wh_zealot_flagellation",
            text = "Gaining temporary health from your level 5 talent also converts permanent health equal to half the temporary health gained.",
        }
    end
    evidence("resolved Devotion internal=%s display_key=%s", state.devotion.name,
        tostring(state.devotion.display_name))
else
    evidence("Devotion unresolved candidates=%d; feature inert", #candidates)
    for i = 1, math.min(#candidates, 12) do
        local c = candidates[i]
        local ok, title = pcall(Localize, c.display_name)
        evidence("candidate name=%s display_key=%s title=%s", c.name,
            tostring(c.display_name), tostring(ok and title or "<loc-error>"))
    end
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
