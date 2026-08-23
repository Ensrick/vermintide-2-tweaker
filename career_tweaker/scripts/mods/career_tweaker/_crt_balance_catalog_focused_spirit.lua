-- Focused Spirit's isolated balance definition (#472). The buffer="both"
-- talent has its own authority/configuration contract, so keeping its catalog
-- row beside that boundary prevents the generic early catalog from growing.

local function build(ctx)
    local mod = assert(ctx.mod, "crt Focused Spirit catalog mod required")
    local policy = assert(mod._crt.focused_spirit,
        "crt Focused Spirit policy required")
    local apply_logged = false

    local function talent()
        if not Talents or not TalentIDLookup then return nil end
        local lookup = TalentIDLookup.kerillian_maidenguard_power_level_on_unharmed
        local hero_talents = lookup and Talents[lookup.hero_name]
        return hero_talents and hero_talents[lookup.talent_id]
    end

    return {
        rework_we_maidenguard_focused_spirit_stacks = {
            character = "kerillian",
            career = "we_maidenguard",
            network_unsafe = true,
            available = function()
                local consensus = mod._crt.focused_spirit_consensus
                return type(consensus) == "table"
                    and type(consensus.all_match) == "function"
                    and consensus:all_match() == true
            end,
            patches = {
                { buff = "kerillian_maidenguard_power_level_on_unharmed", field = "multiplier", value = 0.05 },
                { buff = "kerillian_maidenguard_power_level_on_unharmed", field = "max_stacks", value = 5 },
                { buff = "kerillian_maidenguard_power_level_on_unharmed", field = "remove_on_proc", value = false },
                { buff = "kerillian_maidenguard_power_level_on_unharmed", field = "apply_buff_func", value = "crt_focused_spirit_arm_growth" },
            },
            custom_apply = function(saved)
                local live_talent = talent()
                if not live_talent then return end
                saved.focused_talent_buff_original = live_talent.buffs and live_talent.buffs[1]
                saved.focused_talent_description_values_original = live_talent.description_values
                if live_talent.buffs then
                    live_talent.buffs[1] = "kerillian_maidenguard_power_level_on_unharmed_cooldown"
                end
                live_talent.description = policy.VANILLA_DESCRIPTION_KEY
                live_talent.description_values = {}
                if not apply_logged then
                    apply_logged = true
                    pcall(printf,
                        "[crt:472] applied: talent=%s initial_buff=%s stacks=5 power_per_stack=0.05",
                        policy.VANILLA_DESCRIPTION_KEY,
                        "kerillian_maidenguard_power_level_on_unharmed_cooldown")
                end
            end,
            custom_restore = function(saved)
                local live_talent = talent()
                if not live_talent then return end
                if live_talent.buffs and saved.focused_talent_buff_original ~= nil then
                    live_talent.buffs[1] = saved.focused_talent_buff_original
                end
                if saved.focused_talent_description_values_original ~= nil then
                    live_talent.description_values = saved.focused_talent_description_values_original
                end
                saved.focused_talent_buff_original = nil
                saved.focused_talent_description_values_original = nil
            end,
        },
    }
end

return build
