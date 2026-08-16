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
        H.equal(Core.CANDIDATES[2].source_breed, "chaos_raider")
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

    H.test("ET #451 production remains bounded and observation-only", function()
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
        local clone = {
            name = "chaos_warrior",
            display_name = "vanilla_key",
            max_health = { 60, 90, 120, 150, 210, 210, 210, 210 },
            default_inventory_template = "warrior_axe",
            threat_value = 12,
            race = "chaos",
            armor_category = 3,
        }
        local out = Core.apply_chosen_overrides(clone, spec)
        H.equal(out, clone, "must mutate and return the supplied clone")
        H.equal(out.name, "et_chosen_greataxe")
        H.equal(out.display_name, "et_chosen_greataxe_name")
        H.equal(out.boss_staggers, true)
        H.equal(#out.max_health, 8)
        for i = 1, 8 do H.equal(out.max_health[i], 2000) end
        H.equal(out.default_inventory_template, "warrior_axe")
        -- Untouched fields survive: only the dictated overrides change.
        H.equal(out.threat_value, 12)
        H.equal(out.race, "chaos")
        H.equal(out.armor_category, 3)
    end)

    H.test("ET #451 Chosen override policy fails closed without a clone", function()
        local out, reason = Core.apply_chosen_overrides(nil, Core.CHOSEN)
        H.equal(out, nil)
        H.equal(reason, "breed_clone_missing")
    end)
end
