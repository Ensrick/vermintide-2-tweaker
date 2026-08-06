return function(H, repo_root)
    local Policy = dofile(repo_root
        .. "/career_tweaker/scripts/mods/career_tweaker/_crt_dance_of_blades.lua")

    H.test("CRT #473 Dance stacks exact damage and vulnerability independently", function()
        local templates = Policy.templates()
        H.equal(Policy.validate(templates), true)
        local stack = templates[Policy.stack_buff].buffs
        H.equal(stack[1].multiplier * stack[1].max_stacks, 0.30)
        H.equal(stack[2].multiplier * stack[2].max_stacks, 0.30)
        H.equal(stack[1].refresh_durations, false)
        H.equal(stack[2].refresh_durations, false)
    end)

    H.test("CRT #473 Dance separates blocking dodge from enemy-hit trigger", function()
        local templates = Policy.templates()
        local dodge = templates[Policy.dodge_buff].buffs[1]
        local proc = templates[Policy.proc_buff].buffs[1]
        H.equal(dodge.event, "on_dodge")
        H.equal(dodge.buff_func, "crt_maidenguard_dance_blocking_dodge")
        H.equal(#dodge.dodge_buffs_to_add, 2)
        H.equal(proc.event, "on_hit")
        H.equal(proc.buff_func, "crt_wire_safe_add_buff")
        H.equal(proc.buff_to_add, Policy.stack_buff)
    end)

    H.test("CRT #473 production wiring is reversible and parity gated", function()
        local source = require("crt_source").combined(repo_root)
        H.truthy(source:find("rework_we_maidenguard_dance_of_blades", 1, true))
        H.truthy(source:find("network_unsafe = true", 1, true))
        H.truthy(source:find("dance_talent_buffs_original", 1, true))
        H.truthy(source:find("crt_maidenguard_dance_blocking_dodge", 1, true))
        H.truthy(source:find("BuffTemplates[name] = _crt_make_stub()", 1, true))
    end)

    H.test("CRT #473 setting and talent text are exposed", function()
        local function read(path)
            local f = assert(io.open(path, "rb"))
            local source = f:read("*a")
            f:close()
            return source
        end
        local data = read(repo_root .. "/career_tweaker/scripts/mods/career_tweaker/career_tweaker_data.lua")
        local loc = read(repo_root .. "/career_tweaker/scripts/mods/career_tweaker/career_tweaker_localization.lua")
        local hooks = read(repo_root .. "/career_tweaker/scripts/mods/career_tweaker/_career_tweaker_balance_hooks.lua")
        H.truthy(data:find('setting_id = "rework_we_maidenguard_dance_of_blades"', 1, true))
        H.truthy(loc:find("rework_we_maidenguard_dance_of_blades_description", 1, true))
        H.truthy(hooks:find('["kerillian_maidenguard_versatile_dodge_desc"]', 1, true))
    end)
end
