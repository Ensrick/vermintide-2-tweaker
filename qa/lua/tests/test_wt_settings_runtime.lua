return function(H, repo_root)
    local path = repo_root
        .. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_settings_runtime.lua"
    local Runtime = assert(loadfile(path))()
    local build_registry = dofile(repo_root .. "/qa/lua/fixtures/wt_registry_harness.lua")
    local module_dir = repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/"

    H.test("WT #1002 owner batch performs each full apply exactly once", function()
        local calls = {}
        local function hit(name) calls[name] = (calls[name] or 0) + 1 end
        local mod = {
            _wt374_seed_energy_data = function() hit("energy") end,
            _wt_apply_axe_balance = function(id) hit(id and "balance_one" or "balance_all") end,
            wt_apply_priest_punch_buff = function() hit("priest") end,
            wt_apply_brett_buff = function() hit("brett") end,
        }
        -- WP-WT-07: the batch applies through the real ordered registry.
        local reg = build_registry(module_dir, mod, {
            apply_weapon_unlocks = function() hit("availability") end,
            patch_career_actions = function() hit("actions") end,
            bolt_runtime = { apply = function() hit("bolt") end, revert = function() end },
        })
        Runtime.install({
            mod = mod,
            reconcile = function(reason)
                hit("reconcile:" .. tostring(reason))
                return reg.reconcile(reason)
            end,
            rework_runtime = {
                is_batching = function() return false end,
                on_master_changed = function() return false end,
                sync_for_leaf = function() end,
                prepare_batch = function() hit("rework"); return true end,
            },
            master_toggles = {
                reconcile_batch = function() hit("masters") end,
                on_master_changed = function() end,
                on_child_changed = function() end,
            },
            backend = { refresh_on_setting_change = function() hit("backend") end },
            apply_weapon_unlocks = function() hit("availability") end,
            patch_career_actions = function() hit("actions") end,
            apply_trait_filters = function() hit("traits") end,
            bolt_policy = { SETTING_ID = "bolt" },
            bolt_runtime = { apply = function() hit("bolt") end },
            balance_policy = {},
            extra_batch = function() hit("extra") end,
        })

        local ids = {}
        for i = 1, 300 do ids[i] = "unlock_" .. i end
        mod.on_settings_batch_changed(ids)
        for _, name in ipairs({
            "masters", "rework", "availability", "actions", "energy",
            "backend", "traits", "priest", "brett", "bolt",
            "balance_all", "extra", "reconcile:settings_batch",
        }) do
            H.equal(calls[name], 1, name .. " must remain independent of setting count")
        end
    end)
end
