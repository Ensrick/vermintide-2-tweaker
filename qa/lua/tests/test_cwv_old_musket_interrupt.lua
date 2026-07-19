return function(H, repo_root)
    local policy_path = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_old_musket_interrupt.lua"
    local Policy = assert(loadfile(policy_path))()

    local function sample_template()
        return {
            actions = {
                action_one = {
                    attack = { kind = "sweep", allowed_chain_actions = {
                        { action = "action_two", input = "action_two_hold", start_time = 0.2,
                            sub_action = "default" },
                    } },
                    recovery = { kind = "dummy" },
                },
                action_two = {
                    default = { kind = "block", total_time = math.huge,
                        allowed_chain_actions = {} },
                },
                weapon_reload = {
                    default = { kind = "weapon_reload", allowed_chain_actions = {
                        { action = "action_three", input = "action_three", start_time = 9,
                            sub_action = "default", clear_input = true },
                        { action = "action_three", input = "action_three", start_time = 1,
                            sub_action = "default" },
                    } },
                },
                action_three = {
                    default = { kind = "dummy", allowed_chain_actions = {} },
                },
            },
        }
    end

    H.test("CWV Old Musket special interrupts every running sub-action", function()
        local template = sample_template()
        H.equal(Policy.install(template, "action_three"), 4)
        local ok, covered = Policy.audit(template, "action_three")
        H.truthy(ok)
        H.equal(covered, 4)
        H.equal(#template.actions.action_one.attack.allowed_chain_actions, 2,
            "unrelated native chain must be preserved")
        H.equal(#template.actions.action_three.default.allowed_chain_actions, 0,
            "toggle action must not self-chain")
    end)

    H.test("CWV Old Musket interrupt injection is canonical and idempotent", function()
        local template = sample_template()
        Policy.install(template, "action_three")
        Policy.install(template, "action_three")
        local reload = template.actions.weapon_reload.default.allowed_chain_actions
        local found = {}
        for _, entry in ipairs(reload) do
            if entry.action == "action_three" then found[#found + 1] = entry end
        end
        H.equal(#found, 1)
        H.equal(found[1].start_time, 0)
        H.equal(found[1].clear_buffer, true)
        H.equal(found[1].clear_input, nil)
    end)

    H.test("CWV Old Musket interrupt excludes later career ability rows", function()
        local template = sample_template()
        template.actions.action_career_wh_2 = {
            default = { kind = "career_wh_2", allowed_chain_actions = {} },
        }
        Policy.install(template, "action_three")
        local ok, covered = Policy.audit(template, "action_three")
        H.truthy(ok)
        H.equal(covered, 4)
        H.equal(#template.actions.action_career_wh_2.default.allowed_chain_actions, 0,
            "career activation is not a running weapon action and must not toggle stance")
    end)

    H.test("CWV issue 412 wires both Old Musket templates without new transport", function()
        local source_path = repo_root
            .. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua"
        local file = assert(io.open(source_path, "rb"))
        local source = file:read("*a")
        file:close()
        local _, calls = source:gsub('mod%._cwv_old_musket_interrupt%.install%(template, "action_three"%)', "")
        H.equal(calls, 2)
        H.truthy(source:find('mod._cwv_old_musket_interrupt = mod:dofile(', 1, true))
        H.truthy(source:find('anim_end_event_condition_func = function (unit, end_reason)',
            source:find('local function _create_old_musket_template_melee()', 1, true), true))
    end)
end
