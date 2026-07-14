-- Read-only career passive surfacing (#153).
local mod = get_mod("gut_dev")
local Policy = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_hidden_passive_policy")
local find_profile_index = rawget(_G, "FindProfileIndex")
local career_utils = rawget(_G, "CareerUtils")

local logged = {}

local function career_context(self)
    local hero_name = self and self.hero_name
    local career_index = self and self.career_index
    if type(hero_name) ~= "string" or type(career_index) ~= "number"
            or type(find_profile_index) ~= "function" then
        return nil
    end
    local profile_index = find_profile_index(hero_name)
    local profile = SPProfiles and SPProfiles[profile_index]
    local career = profile and profile.careers and profile.careers[career_index]
    if not career then
        return nil
    end
    local passive = career_utils and career_utils.get_passive_ability_by_career
        and career_utils.get_passive_ability_by_career(career)
    return career, passive
end

local function surface(self)
    if mod:get("gut_surface_hidden_passives") == false then
        return
    end
    local career, passive = career_context(self)
    if not career or not passive then
        return
    end
    local entries = Policy.entries(career.name, career, passive)
    local widget = self._widgets_by_name and self._widgets_by_name.passive_description_text
    if widget and widget.content and #entries > 0 then
        widget.content.text = Policy.append_description(widget.content.text,
            mod:localize("gut_hidden_passive_heading"), entries,
            function(key) return mod:localize(key) end)
    end
    if not logged[career.name] then
        logged[career.name] = true
        mod:info("[gut:153] career=%s buffs=%d vanilla_perks=%d hidden_added=%d display_only=true",
            tostring(career.name), #(passive.buffs or {}), #(passive.perks or {}), #entries)
    end
end

local function install(class_name)
    local class = rawget(_G, class_name)
    if class and class._populate_career_info then
        mod:hook_safe(class, "_populate_career_info", surface)
        return true
    end
    return false
end

local pc_hooked = install("HeroWindowTalents")
local console_hooked = install("HeroWindowTalentsConsole")

mod:command("gut_hidden_passive_probe",
    "Log bounded hidden-career-passive display diagnostics (#153)", function()
        local records = {}
        local passives = {}
        for _, profile in ipairs(SPProfiles or {}) do
            for _, career in ipairs(profile.careers or {}) do
                records[#records + 1] = career
                if career_utils and career_utils.get_passive_ability_by_career then
                    passives[career.name] = career_utils.get_passive_ability_by_career(career)
                end
            end
        end
        local result = Policy.inspect(records, passives)
        mod:info("[gut:153] probe careers=%d catalogued=%d pc_hook=%s console_hook=%s",
            result.career_count, result.catalogued_count, tostring(pc_hooked), tostring(console_hooked))
        for _, record in ipairs(result.records) do
            mod:info("[gut:153] probe career=%s buffs=%d vanilla_perks=%d hidden=%d",
                record.name, record.buff_count, record.vanilla_perk_count, record.hidden_count)
        end
    end)

return {
    policy = Policy,
    rt_checks = {
        {
            name = "issue153_hidden_passives_display_only",
            fn = function()
                if not pc_hooked and not console_hooked then
                    return "neither talent-window hook installed"
                end
                local sample = {
                    name = "wh_captain",
                    attributes = { base_critical_strike_chance = 0.1 },
                }
                local entries = Policy.entries("wh_captain", sample, {
                    buffs = { "victor_witchhunter_headshot_multiplier_increase" },
                })
                if #entries ~= 2 then
                    return "WHC source-derived hidden-passive catalog incomplete"
                end
                return nil
            end,
        },
    },
}
