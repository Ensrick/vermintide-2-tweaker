-- Pure constants/template factory for Handmaiden Dance of Blades (#473).
local M = {
    duration = 2,
    max_stacks = 15,
    damage_per_stack = 0.02,
    damage_taken_per_stack = 0.02,
    dodge_distance_multiplier = 1.2,
    dodge_buff = "crt_maidenguard_dance_of_blades_dodge",
    proc_buff = "crt_maidenguard_dance_of_blades_proc",
    stack_buff = "crt_maidenguard_dance_of_blades_stack",
}

function M.templates()
    return {
        [M.dodge_buff] = {
            buffs = { {
                buff_func = "crt_maidenguard_dance_blocking_dodge",
                dodge_buffs_to_add = {
                    "kerillian_maidenguard_improved_dodge",
                    "kerillian_maidenguard_improved_dodge_speed",
                },
                event = "on_dodge",
                name = M.dodge_buff,
            } },
        },
        [M.proc_buff] = {
            buffs = { {
                buff_func = "crt_wire_safe_add_buff",
                buff_to_add = M.stack_buff,
                event = "on_kill",
                name = M.proc_buff,
            } },
        },
        [M.stack_buff] = {
            buffs = {
                {
                    duration = M.duration,
                    icon = "kerillian_maidenguard_cooldown_on_nearby_allies",
                    max_stacks = M.max_stacks,
                    multiplier = M.damage_per_stack,
                    name = M.stack_buff,
                    refresh_durations = false,
                    stat_buff = "damage_dealt",
                },
                {
                    duration = M.duration,
                    max_stacks = M.max_stacks,
                    multiplier = M.damage_taken_per_stack,
                    name = M.stack_buff,
                    refresh_durations = false,
                    stacking_name = "crt_maidenguard_dance_of_blades_damage_taken",
                    stat_buff = "damage_taken",
                },
            },
        },
    }
end

function M.validate(templates)
    local dodge = templates and templates[M.dodge_buff]
    local proc = templates and templates[M.proc_buff]
    local stack = templates and templates[M.stack_buff]
    local db = dodge and dodge.buffs and dodge.buffs[1]
    local pb = proc and proc.buffs and proc.buffs[1]
    local damage = stack and stack.buffs and stack.buffs[1]
    local taken = stack and stack.buffs and stack.buffs[2]
    return db and db.event == "on_dodge"
        and pb and pb.event == "on_kill" and pb.buff_to_add == M.stack_buff
        and damage and damage.stat_buff == "damage_dealt"
        and damage.multiplier == 0.02 and damage.max_stacks == 15
        and damage.duration == 2 and damage.refresh_durations == false
        and taken and taken.stat_buff == "damage_taken"
        and taken.multiplier == 0.02 and taken.max_stacks == 15
        and taken.duration == 2 and taken.refresh_durations == false
        and true or false
end

return M
