-- WP-WT-01: disabling wt / wt_dev must leave every hero able to wield its own
-- weapons. clear_weapon_unlocks used to strip every career of every
-- weapon_unlock_map pair, native pairs included (dr_ranger on dr_1h_axe is
-- vanilla: Vermintide-2-Source-Code/scripts/settings/equipment/
-- item_master_list_exported.lua:7273-7277). Loads the production
-- _wt_availability.lua of both trees in a sandbox and drives apply/clear.

return function(H, repo_root)
    local trees = {
        { mod_name = "wt", root = repo_root .. "/weapon_tweaker/",
          module = "scripts/mods/weapon_tweaker/_wt_availability" },
        { mod_name = "wt_dev", root = repo_root .. "/weapon_tweaker_dev/",
          module = "scripts/mods/weapon_tweaker_dev/_wt_availability" },
    }

    local function contains(list, wanted)
        for _, value in ipairs(list or {}) do
            if value == wanted then return true end
        end
        return false
    end

    local function assert_no_duplicates(iml)
        for weapon_key, item in pairs(iml) do
            local seen = {}
            for _, career in ipairs(item.can_wield or {}) do
                H.equal(seen[career], nil, weapon_key .. " lists " .. career .. " twice")
                seen[career] = true
            end
        end
    end

    local function fresh_item_master_list()
        return {
            dr_1h_axe = { can_wield = { "dr_ironbreaker", "dr_slayer", "dr_ranger" } },
            es_1h_sword = { can_wield = { "es_mercenary", "es_huntsman", "es_knight" } },
            wh_crossbow = { can_wield = { "wh_captain", "wh_bountyhunter", "wh_zealot", "xx_other_mod" } },
        }
    end

    local function load_tree(tree, settings)
        local iml = fresh_item_master_list()
        local mod = {
            _wt = {
                weapon_unlock_map = {
                    dr_ranger = { "dr_1h_axe", "es_1h_sword" },
                    es_mercenary = { "wh_crossbow" },
                },
                cwv_conditional_managed = {},
            },
        }
        local env
        local function load_into_env(path)
            local chunk = assert(loadfile(path))
            setfenv(chunk, env)
            return chunk()
        end
        env = setmetatable({
            ItemMasterList = iml,
            get_mod = function(name)
                if name == tree.mod_name then return mod end
                return nil
            end,
        }, { __index = _G })
        function mod.get(_, id) return settings[id] end
        function mod.set() end
        function mod.info() end
        function mod.error() end
        function mod.dofile(_, path) return load_into_env(tree.root .. path .. ".lua") end
        load_into_env(tree.root .. tree.module .. ".lua")
        return mod, iml
    end

    for _, tree in ipairs(trees) do
        H.test(tree.mod_name .. " disable restores native careers and strips only WT cross pairs", function()
            local mod, iml = load_tree(tree, {
                unlock_dr_ranger_dr_1h_axe = true,
                unlock_dr_ranger_es_1h_sword = true,
                unlock_es_mercenary_wh_crossbow = true,
            })
            mod._wt.apply_weapon_unlocks()
            H.truthy(contains(iml.dr_1h_axe.can_wield, "dr_ranger"), "apply dropped native dr_ranger")
            H.truthy(contains(iml.es_1h_sword.can_wield, "dr_ranger"), "apply did not add dr_ranger to es_1h_sword")
            H.truthy(contains(iml.wh_crossbow.can_wield, "es_mercenary"), "apply did not add es_mercenary to wh_crossbow")
            assert_no_duplicates(iml)

            mod._wt.clear_weapon_unlocks()
            H.truthy(contains(iml.dr_1h_axe.can_wield, "dr_ranger"),
                "disable stripped native dr_ranger from dr_1h_axe")
            H.equal(contains(iml.es_1h_sword.can_wield, "dr_ranger"), false,
                "disable left cross-career dr_ranger on es_1h_sword")
            H.equal(contains(iml.wh_crossbow.can_wield, "es_mercenary"), false,
                "disable left cross-career es_mercenary on wh_crossbow")
            H.truthy(contains(iml.wh_crossbow.can_wield, "xx_other_mod"),
                "disable removed another mod's career")
            assert_no_duplicates(iml)
        end)

        H.test(tree.mod_name .. " native toggle off removes while enabled and disable puts it back", function()
            local mod, iml = load_tree(tree, {
                unlock_dr_ranger_dr_1h_axe = false,
                unlock_dr_ranger_es_1h_sword = true,
                unlock_es_mercenary_wh_crossbow = true,
            })
            mod._wt.apply_weapon_unlocks()
            H.equal(contains(iml.dr_1h_axe.can_wield, "dr_ranger"), false,
                "native toggle off must remove dr_ranger while enabled")
            assert_no_duplicates(iml)

            mod._wt.clear_weapon_unlocks()
            H.truthy(contains(iml.dr_1h_axe.can_wield, "dr_ranger"),
                "disable did not restore native dr_ranger on dr_1h_axe")
            H.equal(contains(iml.es_1h_sword.can_wield, "dr_ranger"), false)
            H.equal(contains(iml.wh_crossbow.can_wield, "es_mercenary"), false)
            H.truthy(contains(iml.wh_crossbow.can_wield, "xx_other_mod"))
            assert_no_duplicates(iml)
        end)
    end
end
