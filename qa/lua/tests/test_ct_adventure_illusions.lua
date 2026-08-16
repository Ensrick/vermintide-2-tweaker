-- #917 Preserve Adventure weapon illusions in CW: behavioral tests driving the
-- REAL shipped module (loadfile) through in-game-reachable flows - pilgrimage
-- start snapshot via the DeusMechanism._setup_run seam, compatibility-gated
-- application on generation, upgrade carry, and the exclusion brackets.
return function(H, repo_root)
    local base = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
    local module_path = base .. "_ct_adventure_illusions.lua"

    -- Adventure skin items as ItemMasterList models them: the skin item's
    -- matching_item_key names the one weapon family it fits
    -- (item_master_list.lua:80-83).
    local FAKE_ITEM_MASTER = {
        es_1h_mace_skin_02 = { slot_type = "weapon_skin", matching_item_key = "es_1h_mace" },
        es_2h_sword_skin_01 = { slot_type = "weapon_skin", matching_item_key = "es_2h_sword" },
        wh_1h_axe_skin_03 = { slot_type = "weapon_skin", matching_item_key = "wh_1h_axe" },
    }

    local function load_world(settings)
        local saved = { Managers = _G.Managers, ItemMasterList = _G.ItemMasterList }
        local world = { settings = settings or {}, hooks = {} }
        local fake_mod = {}
        function fake_mod:get(setting_id)
            return world.settings[setting_id]
        end
        function fake_mod:hook(class_name, method_name, fn)
            world.hooks[tostring(class_name) .. "." .. tostring(method_name)] = fn
        end
        _G.ItemMasterList = FAKE_ITEM_MASTER
        local installer = assert(loadfile(module_path))()
        world.module = installer({ mod = fake_mod })
        world.mod = fake_mod
        world.restore = function()
            _G.Managers = saved.Managers
            _G.ItemMasterList = saved.ItemMasterList
        end
        return world
    end

    -- Backend items model: get_loadout() career->slot->backend_id and
    -- get_item_from_id(id) -> { key, skin } (backend_interface_item_playfab.lua
    -- get_skin :344-347 reads item.skin the same way).
    local function wire_backend(world, loadout, items_by_id, current_career)
        _G.Managers = {
            backend = {
                get_interface = function(_, name)
                    if name ~= "items" then return nil end
                    return {
                        get_loadout = function() return loadout end,
                        get_item_from_id = function(_, backend_id)
                            return items_by_id[backend_id]
                        end,
                    }
                end,
            },
            player = {
                local_player = function()
                    return {
                        career_name = function() return current_career end,
                    }
                end,
            },
        }
    end

    H.test("CT #917 compatibility gate: wrong-family skin never passes", function()
        local world = load_world({ preserve_adventure_illusions = true })
        local ok, failure = pcall(function()
            local M = world.module
            H.equal(M.compatible("es_1h_mace_skin_02", "es_1h_mace", FAKE_ITEM_MASTER), true)
            H.equal(M.compatible("es_2h_sword_skin_01", "es_1h_mace", FAKE_ITEM_MASTER), false,
                "wrong-family skin must be rejected")
            H.equal(M.compatible("no_such_skin", "es_1h_mace", FAKE_ITEM_MASTER), false)
            H.equal(M.compatible(nil, "es_1h_mace", FAKE_ITEM_MASTER), false)
            H.equal(M.compatible("es_1h_mace_skin_02", nil, FAKE_ITEM_MASTER), false)
        end)
        world.restore()
        if not ok then error(failure, 0) end
    end)

    H.test("CT #917 snapshot captures only compatible melee/ranged skins, current career wins", function()
        local world = load_world({ preserve_adventure_illusions = true })
        local ok, failure = pcall(function()
            local M = world.module
            local loadout = {
                es_knight = { slot_melee = 1, slot_ranged = 2, slot_hat = 9 },
                es_mercenary = { slot_melee = 3 },
                wh_captain = { slot_melee = 4, slot_ranged = 5 },
            }
            local items_by_id = {
                -- both es careers carry the same family with DIFFERENT skins
                [1] = { key = "es_1h_mace", skin = "es_1h_mace_skin_02" },
                [3] = { key = "es_1h_mace", skin = "wrong_pool_skin" },
                [2] = { key = "es_2h_sword", skin = "es_2h_sword_skin_01" },
                [4] = { key = "wh_1h_axe" }, -- no illusion equipped
                [5] = { key = "wh_crossbow", skin = "es_1h_mace_skin_02" }, -- cross-family pollution
                [9] = { key = "es_hat_01", skin = "es_1h_mace_skin_02" }, -- non-weapon slot
            }
            local get_item = function(id) return items_by_id[id] end
            local snapshot = M.build_snapshot(loadout, get_item, FAKE_ITEM_MASTER, "es_knight")
            H.equal(snapshot.es_1h_mace, "es_1h_mace_skin_02",
                "current career's skin wins the family collision")
            H.equal(snapshot.es_2h_sword, "es_2h_sword_skin_01")
            H.equal(snapshot.wh_1h_axe, nil, "slot without an illusion stays absent")
            H.equal(snapshot.wh_crossbow, nil,
                "a skin that does not match its own item never enters the snapshot")
            H.equal(snapshot.es_hat_01, nil, "non-weapon slots are ignored")
        end)
        world.restore()
        if not ok then error(failure, 0) end
    end)

    H.test("CT #917 pilgrimage-start snapshot feeds compatibility-gated generation", function()
        local world = load_world({ preserve_adventure_illusions = true })
        local ok, failure = pcall(function()
            local M = world.module
            wire_backend(world,
                { es_knight = { slot_melee = 1 } },
                { [1] = { key = "es_1h_mace", skin = "es_1h_mace_skin_02" } },
                "es_knight")
            -- snapshot_now is what the merged DeusMechanism._setup_run hook in
            -- _ct_run_runtime_owner.lua calls PRE-vanilla at pilgrimage start
            local snapshot = M.snapshot_now()
            H.equal(type(snapshot), "table")
            H.equal(snapshot.es_1h_mace, "es_1h_mace_skin_02")
            -- the snapshot feeds generation: starter/swap of the same family
            local starter = M.apply_to_result("generate_item_from_item_key",
                { key = "es_1h_mace", skin = "random_roll", rarity = "plentiful" })
            H.equal(starter.skin, "es_1h_mace_skin_02", "same-family generation keeps the illusion")
            local swap = M.apply_to_result("generate_weapon_for_slot",
                { key = "es_2h_sword", skin = "vanilla_roll", rarity = "exotic" })
            H.equal(swap.skin, "vanilla_roll",
                "family without a saved illusion stays vanilla (wrong-family never applied)")
        end)
        world.restore()
        if not ok then error(failure, 0) end
    end)

    H.test("CT #917 default-OFF toggle keeps everything vanilla", function()
        local world = load_world({ preserve_adventure_illusions = false })
        local ok, failure = pcall(function()
            local M = world.module
            wire_backend(world,
                { es_knight = { slot_melee = 1 } },
                { [1] = { key = "es_1h_mace", skin = "es_1h_mace_skin_02" } },
                "es_knight")
            H.equal(M.snapshot_now(), nil, "toggle off takes no snapshot")
            local result = M.apply_to_result("generate_item_from_item_key",
                { key = "es_1h_mace", skin = "random_roll", rarity = "plentiful" })
            H.equal(result.skin, "random_roll", "toggle off never mutates generation")
        end)
        world.restore()
        if not ok then error(failure, 0) end
    end)

    H.test("CT #917 upgrades carry the item's own compatible skin, never the snapshot", function()
        local world = load_world({ preserve_adventure_illusions = true })
        local ok, failure = pcall(function()
            local M = world.module
            wire_backend(world,
                { es_knight = { slot_melee = 1 } },
                { [1] = { key = "es_1h_mace", skin = "es_1h_mace_skin_02" } },
                "es_knight")
            M.snapshot_now()
            -- vanilla rerolled the skin on upgrade; the prior item's compatible
            -- skin is restored (serialized item.skin is the carrier)
            local upgraded = M.apply_to_result("upgrade_item",
                { key = "es_2h_sword", skin = "unique_reroll", rarity = "unique" },
                { key = "es_2h_sword", skin = "es_2h_sword_skin_01", rarity = "exotic" })
            H.equal(upgraded.skin, "es_2h_sword_skin_01", "upgrade carries the current skin")
            -- wrong-family prior skin (cross-key pollution) must never carry
            local polluted = M.apply_to_result("upgrade_item",
                { key = "es_2h_sword", skin = "unique_reroll", rarity = "unique" },
                { key = "es_2h_sword", skin = "es_1h_mace_skin_02", rarity = "exotic" })
            H.equal(polluted.skin, "unique_reroll",
                "wrong-family prior skin never carries through an upgrade")
            -- prior item without a skin: snapshot must NOT leak onto upgrades
            local no_prior = M.apply_to_result("upgrade_item",
                { key = "es_1h_mace", skin = "unique_reroll", rarity = "unique" },
                { key = "es_1h_mace", rarity = "exotic" })
            H.equal(no_prior.skin, "unique_reroll",
                "snapshot never applies on the upgrade path")
        end)
        world.restore()
        if not ok then error(failure, 0) end
    end)

    H.test("CT #917 suppression brackets exclude bot mirroring", function()
        local world = load_world({ preserve_adventure_illusions = true })
        local ok, failure = pcall(function()
            local M = world.module
            wire_backend(world,
                { es_knight = { slot_melee = 1 } },
                { [1] = { key = "es_1h_mace", skin = "es_1h_mace_skin_02" } },
                "es_knight")
            M.snapshot_now()
            M.suppress(true)
            local suppressed = M.apply_to_result("generate_weapon_for_slot",
                { key = "es_1h_mace", skin = "bot_roll", rarity = "exotic" })
            H.equal(suppressed.skin, "bot_roll", "explicit suppress bracket holds")
            M.suppress(false)
            world.mod._ct_bot_weapon_chest_owner_state = { bot_weapon_mirror_active = true }
            local bot_roll = M.apply_to_result("generate_weapon_for_slot",
                { key = "es_1h_mace", skin = "bot_roll", rarity = "exotic" })
            H.equal(bot_roll.skin, "bot_roll", "bot chest mirroring stays vanilla")
            world.mod._ct_bot_weapon_chest_owner_state = { bot_weapon_mirror_active = false }
            local player_roll = M.apply_to_result("generate_weapon_for_slot",
                { key = "es_1h_mace", skin = "player_roll", rarity = "exotic" })
            H.equal(player_roll.skin, "es_1h_mace_skin_02",
                "player generation applies again once the bracket lifts")
            H.equal(M.regression_check(), nil, "runtime regression check passes")
        end)
        world.restore()
        if not ok then error(failure, 0) end
    end)
end
