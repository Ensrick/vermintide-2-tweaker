return function(H, repo_root)
    local path = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_replay_policy.lua"
    local chunk, err = loadfile(path)
    if not chunk then error(err) end
    local Policy = chunk()

    H.test("Cosmetics persisted LA replay waits for realized inventory", function()
        H.equal(false, Policy.inventory_ready(nil))
        H.equal(false, Policy.inventory_ready({}))
        H.equal(false, Policy.inventory_ready({ _equipment = { slots = {} } }))
        H.equal(false, Policy.inventory_ready({
            _equipment = { slots = { slot_hat = { item_data = {} } } },
        }))
    end)

    H.test("Cosmetics persisted LA replay accepts either realized weapon slot", function()
        H.equal(true, Policy.inventory_ready({
            _equipment = { slots = { slot_melee = { item_data = { backend_id = "m" } } } },
        }))
        H.equal(true, Policy.inventory_ready({
            equipment = { slots = { slot_ranged = { item_data = { backend_id = "r" } } } },
        }))
    end)
end
