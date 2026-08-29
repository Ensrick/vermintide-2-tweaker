return function(H, repo_root)
    local Core = assert(loadfile(repo_root
        .. "/enemy_tweaker/scripts/mods/enemy_tweaker/_et_boss_ideas_core.lua"))()

    local function complete_context(resident)
        local context = {
            breeds = {}, actions = {}, behaviors = {}, inventories = {},
            breed_lookup = {}, unit_resident = function() return resident end,
        }
        for _, candidate in ipairs(Core.CANDIDATES) do
            local source = candidate.source_breed
            local model = candidate.model_breed or source
            context.breeds[source] = context.breeds[source] or {
                base_unit = "unit/" .. source,
                behavior = "behavior_" .. source,
                default_inventory_template = "inventory_" .. source,
            }
            context.breeds[model] = context.breeds[model] or {
                base_unit = "unit/" .. model,
                behavior = "behavior_" .. model,
            }
            context.actions[source] = {}
            context.behaviors["behavior_" .. source] = {}
            context.inventories["inventory_" .. source] = {}
            context.breed_lookup[source] = 1
        end
        return context
    end

    H.test("ET #451 catalog retains six bounded boss concepts", function()
        H.equal(#Core.CANDIDATES, 6)
        H.equal(Core.CANDIDATES[1].id, "chosen_shield")
        H.equal(Core.CANDIDATES[2].source_breed, "chaos_warrior")
        H.equal(Core.CANDIDATES[6].source_breed, "chaos_troll_chief")
    end)

    H.test("ET #451 complete source contracts remain diagnostics-only inputs", function()
        local result = Core.inspect(complete_context(true))
        H.equal(#result.rows, 6)
        H.equal(result.missing_breeds, 0)
        H.equal(result.structure_ready, 6)
        H.equal(result.resident_models, 6)
    end)

    H.test("ET #451 census separates structure from package residency", function()
        local context = complete_context(false)
        context.actions.skaven_grey_seer = nil
        context.breed_lookup.chaos_troll_chief = nil
        local result = Core.inspect(context)
        H.equal(result.missing_breeds, 0)
        H.equal(result.structure_ready, 4)
        H.equal(result.resident_models, 0)
        H.equal(result.rows[4].actions_present, false)
        H.equal(result.rows[6].wire_present, false)
    end)

    H.test("ET #451 census fails closed on absent globals", function()
        local result = Core.inspect(nil)
        H.equal(#result.rows, 6)
        H.equal(result.missing_breeds, 6)
        H.equal(result.structure_ready, 0)
        H.equal(result.resident_models, 0)
    end)

    H.test("ET #451 census and explicit prototype surfaces remain bounded", function()
        local path = repo_root
            .. "/enemy_tweaker/scripts/mods/enemy_tweaker/_et_boss_ideas.lua"
        local handle = assert(io.open(path, "rb"))
        local source = handle:read("*a")
        handle:close()
        H.equal(source:find('mod:command("et_boss_idea_audit"', 1, true) ~= nil, true)
        H.equal(source:find('app.can_get', 1, true) ~= nil, true)
        H.equal(source:find("mod:hook", 1, true), nil)
        H.equal(source:find("mod:network_register", 1, true), nil)
        H.equal(source:find("spawn_network_unit", 1, true), nil)
    end)

    H.test("ET #451 Chosen override policy builds the dictated prototype", function()
        local spec = Core.CHOSEN
        H.equal(spec.name, "et_chosen_greataxe")
        H.equal(spec.source_breed, "chaos_warrior")
        H.equal(spec.inventory_template, "warrior_axe")
        H.equal(spec.threat_value, 32)
        local donor_spawn = function() return "donor-spawn" end
        local source = {
            name = "chaos_warrior",
            display_name = "vanilla_key",
            max_health = { 60, 90, 120, 150, 210, 210, 210, 210 },
            default_inventory_template = "warrior_axe",
            threat_value = 12,
            race = "chaos",
            armor_category = 3,
            elite = true,
            category_mask = 4,
            infighting = { kind = "large" },
            run_on_spawn = donor_spawn,
        }
        local clone = {}
        for key, value in pairs(source) do clone[key] = value end
        clone.max_health = { unpack(source.max_health) }
        local boss_infighting = { kind = "boss" }
        local counts = { add_boss = 0, add_angry = 0, remove_boss = 0, remove_angry = 0 }
        local services = {
            boss_infighting = boss_infighting,
            inject_breed_category_mask = function(breed)
                H.equal(breed.boss, true, "category injection must run after boss classification")
                H.equal(breed.elite, nil, "category injection must run after elite removal")
                breed.category_mask = 64 + (breed.armor_category or 0)
            end,
            add_boss = function() counts.add_boss = counts.add_boss + 1 end,
            add_angry = function() counts.add_angry = counts.add_angry + 1 end,
            remove_boss = function() counts.remove_boss = counts.remove_boss + 1 end,
            remove_angry = function() counts.remove_angry = counts.remove_angry + 1 end,
        }
        local out = Core.apply_chosen_overrides(clone, spec, services)
        H.equal(out, clone, "must mutate and return the supplied clone")
        H.equal(out.name, "et_chosen_greataxe")
        H.equal(out.display_name, "et_chosen_greataxe_name")
        H.equal(out.boss_staggers, true)
        H.equal(out.boss, true)
        H.equal(out.elite, nil)
        H.equal(out.show_health_bar, true)
        H.equal(out.far_off_despawn_immunity, true)
        H.equal(out.threat_value, 32)
        H.equal(out.infighting, boss_infighting)
        H.equal(out.category_mask, 67)
        H.equal(#out.max_health, 8)
        for i = 1, 8 do H.equal(out.max_health[i], 2000) end
        H.equal(out.default_inventory_template, "warrior_axe")
        -- Unrelated fields survive; the vanilla donor remains byte-for-byte
        -- untouched while only the clone receives boss classification.
        H.equal(out.race, "chaos")
        H.equal(out.armor_category, 3)
        H.equal(source.name, "chaos_warrior")
        H.equal(source.elite, true)
        H.equal(source.threat_value, 12)
        H.equal(source.category_mask, 4)
        H.equal(source.run_on_spawn, donor_spawn)
    end)

    H.test("ET #451 Chosen lifecycle preserves donors and registers/removes boss state exactly once", function()
        local calls = {
            donor_spawn = 0, donor_death = 0, donor_despawn = 0,
            add_boss = 0, add_angry = 0, remove_boss = 0, remove_angry = 0,
        }
        local breed = {
            run_on_spawn = function(_, _, value)
                calls.donor_spawn = calls.donor_spawn + 1
                return "spawn", value
            end,
            run_on_death = function()
                calls.donor_death = calls.donor_death + 1
                return "death"
            end,
            run_on_despawn = function()
                calls.donor_despawn = calls.donor_despawn + 1
                return "despawn"
            end,
        }
        local donor_spawn, donor_death, donor_despawn = breed.run_on_spawn,
            breed.run_on_death, breed.run_on_despawn
        local services = {
            add_boss = function() calls.add_boss = calls.add_boss + 1 end,
            add_angry = function() calls.add_angry = calls.add_angry + 1 end,
            remove_boss = function() calls.remove_boss = calls.remove_boss + 1 end,
            remove_angry = function() calls.remove_angry = calls.remove_angry + 1 end,
        }
        assert(Core.wrap_chosen_lifecycle(breed, services))
        local unit, blackboard = {}, {}
        local a, b = breed.run_on_spawn(unit, blackboard, 17)
        H.equal(a, "spawn")
        H.equal(b, 17)
        breed.run_on_spawn(unit, blackboard, 18)
        H.equal(calls.donor_spawn, 2, "donor spawn remains per-callback")
        H.equal(calls.add_boss, 1)
        H.equal(calls.add_angry, 1)
        H.equal(blackboard.is_angry, true)
        H.equal(breed.run_on_death(unit, blackboard), "death")
        H.equal(breed.run_on_despawn(unit, blackboard), "despawn")
        H.equal(calls.donor_death, 1)
        H.equal(calls.donor_despawn, 1)
        H.equal(calls.remove_boss, 1, "death+despawn share one boss removal")
        H.equal(calls.remove_angry, 1, "death+despawn share one angry removal")
        H.equal(blackboard.is_angry, false)
        H.equal(type(donor_spawn), "function")
        H.equal(type(donor_death), "function")
        H.equal(type(donor_despawn), "function")
    end)

    H.test("ET #451 Chosen lifecycle runs remaining operations after errors without retrying side effects", function()
        local calls = { donor = 0, boss = 0, angry = 0, remove_boss = 0, remove_angry = 0 }
        local breed = {
            run_on_spawn = function()
                calls.donor = calls.donor + 1
                error("donor exploded")
            end,
        }
        assert(Core.wrap_chosen_lifecycle(breed, {
            add_boss = function()
                calls.boss = calls.boss + 1
                error("boss exploded after mutation")
            end,
            add_angry = function() calls.angry = calls.angry + 1 end,
            remove_boss = function() calls.remove_boss = calls.remove_boss + 1 end,
            remove_angry = function()
                calls.remove_angry = calls.remove_angry + 1
                error("angry cleanup exploded")
            end,
        }))
        local unit, blackboard = {}, {}
        local ok, err = pcall(breed.run_on_spawn, unit, blackboard)
        H.equal(ok, false)
        H.equal(tostring(err):find("donor exploded", 1, true) ~= nil, true,
            "first donor error must be preserved")
        H.equal(calls.boss, 1)
        H.equal(calls.angry, 1, "angry registration still runs after earlier errors")
        pcall(breed.run_on_spawn, unit, blackboard)
        H.equal(calls.donor, 2)
        H.equal(calls.boss, 1, "failed side effect is attempt-once")
        H.equal(calls.angry, 1)
        local death_ok, death_err = pcall(breed.run_on_death, unit, blackboard)
        H.equal(death_ok, false)
        H.equal(tostring(death_err):find("angry cleanup exploded", 1, true) ~= nil, true)
        H.equal(calls.remove_boss, 1)
        H.equal(calls.remove_angry, 1)
        pcall(breed.run_on_despawn, unit, blackboard)
        H.equal(calls.remove_boss, 1)
        H.equal(calls.remove_angry, 1)
    end)

    H.test("ET #451 Chosen lifecycle preserves nil error payloads", function()
        local angry = 0
        local breed = { run_on_spawn = function() error(nil, 0) end }
        assert(Core.wrap_chosen_lifecycle(breed, {
            add_boss = function() end,
            add_angry = function() angry = angry + 1 end,
            remove_boss = function() end,
            remove_angry = function() end,
        }))
        local ok, err = pcall(breed.run_on_spawn, {}, {})
        H.equal(ok, false, "nil error payload was swallowed")
        H.equal(err, nil)
        H.equal(angry, 1, "later lifecycle operation did not run")
    end)

    H.test("ET #451 Chosen override policy fails closed without a clone", function()
        local out, reason = Core.apply_chosen_overrides(nil, Core.CHOSEN)
        H.equal(out, nil)
        H.equal(reason, "breed_clone_missing")
    end)

    H.test("ET #451 Chosen override policy fails closed without boss services", function()
        local out, reason = Core.apply_chosen_overrides({}, Core.CHOSEN, {})
        H.equal(out, nil)
        H.equal(reason, "boss_infighting_missing")
    end)
end
