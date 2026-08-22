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
    damage_stack = "crt_maidenguard_dance_of_blades_damage",
    damage_taken_stack = "crt_maidenguard_dance_of_blades_damage_taken",
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
                authority = "server",
                event = "on_hit",
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
                    name = M.damage_stack,
                    refresh_durations = false,
                    stat_buff = "damage_dealt",
                },
                {
                    duration = M.duration,
                    max_stacks = M.max_stacks,
                    multiplier = M.damage_taken_per_stack,
                    name = M.damage_taken_stack,
                    refresh_durations = false,
                    stacking_name = M.damage_taken_stack,
                    stat_buff = "damage_taken",
                },
            },
        },
    }
end

local function exact_array(value, size)
    if type(value) ~= "table" then return false end
    for i = 1, size do
        if value[i] == nil then return false end
    end
    for key in pairs(value) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > size then
            return false
        end
    end
    return true
end

function M.validate(templates)
    if type(templates) ~= "table" then return false end
    local dodge = templates[M.dodge_buff]
    local proc = templates[M.proc_buff]
    local stack = templates[M.stack_buff]
    if type(dodge) ~= "table" or not exact_array(dodge.buffs, 1)
        or type(proc) ~= "table" or not exact_array(proc.buffs, 1)
        or type(stack) ~= "table" or not exact_array(stack.buffs, 2) then
        return false
    end
    local db = dodge.buffs[1]
    local pb = proc.buffs[1]
    local damage = stack.buffs[1]
    local taken = stack.buffs[2]
    return type(db) == "table" and db.name == M.dodge_buff and db.event == "on_dodge"
        and db.buff_func == "crt_maidenguard_dance_blocking_dodge"
        and exact_array(db.dodge_buffs_to_add, 2)
        and db.dodge_buffs_to_add[1] == "kerillian_maidenguard_improved_dodge"
        and db.dodge_buffs_to_add[2] == "kerillian_maidenguard_improved_dodge_speed"
        and type(pb) == "table" and pb.name == M.proc_buff and pb.event == "on_hit"
        and pb.buff_func == "crt_wire_safe_add_buff"
        and pb.buff_to_add == M.stack_buff and pb.authority == "server"
        and type(damage) == "table" and damage.name == M.damage_stack
        and damage.name ~= M.damage_taken_stack
        and damage.stat_buff == "damage_dealt"
        and damage.multiplier == M.damage_per_stack
        and damage.max_stacks == M.max_stacks
        and damage.duration == M.duration and damage.refresh_durations == false
        and type(taken) == "table" and taken.name == M.damage_taken_stack
        and taken.name ~= M.damage_stack
        and taken.stacking_name == M.damage_taken_stack
        and taken.stat_buff == "damage_taken"
        and taken.multiplier == M.damage_taken_per_stack
        and taken.max_stacks == M.max_stacks
        and taken.duration == M.duration and taken.refresh_durations == false
        and true or false
end

return M
