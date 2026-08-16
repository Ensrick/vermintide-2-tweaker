return function(H, repo_root)
    local policy_path = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_weapon_pose_policy.lua"
    local module_path = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_weapon_poses.lua"
    local Policy = dofile(policy_path)

    -- Authored rows mirror the shipped shapes (item_master_list_weapon_poses):
    -- the backendless "default" row carries data = {} and must stay excluded;
    -- posed rows are animation-backed.
    local function authored_master()
        return {
            default_weapon_pose_01 = { item_type = "weapon_pose",
                parent = "default", pose_index = 1, data = {} },
            es_2h_hammer_pose_02 = { item_type = "weapon_pose",
                parent = "es_2h_hammer", pose_index = 2,
                data = { anim_event = "anim_pose_02" } },
            es_2h_hammer_pose_01 = { item_type = "weapon_pose",
                parent = "es_2h_hammer", pose_index = 1,
                data = { anim_event = "anim_pose_01" } },
            we_sword_dagger_pose_01 = { item_type = "weapon_pose",
                parent = "we_dual_wield_sword_dagger", pose_index = 1,
                data = { anim_event = "anim_pose_01", hide_weapons = false } },
            es_2h_hammer = { item_type = "es_2h_war_hammer",
                template = "two_handed_hammers_template_1" },
        }
    end

    H.test("Cosmetics authored pose catalog is parent-scoped and sorted", function()
        local master = {
            pose_b = { item_type = "weapon_pose", parent = "sword", pose_index = 2, data = { anim_event = "anim_pose_02" } },
            pose_a = { item_type = "weapon_pose", parent = "sword", pose_index = 1, data = { anim_event = "anim_pose_01" } },
            axe_pose = { item_type = "weapon_pose", parent = "axe", pose_index = 1, data = { anim_event = "anim_pose_01" } },
            malformed = { item_type = "weapon_pose", parent = "sword", pose_index = 3 },
            ordinary = { item_type = "weapon_skin", parent = "sword", pose_index = 4, data = { anim_event = "bad" } },
        }
        local catalog = Policy.build_catalog(master)
        local sword = Policy.for_parent(catalog, "sword")
        H.equal(#sword, 2)
        H.equal(sword[1].ItemId, "pose_a")
        H.equal(sword[2].ItemId, "pose_b")
        H.equal(#Policy.for_parent(catalog, "axe"), 1)
        H.equal(Policy.for_parent(catalog, "missing"), nil)
    end)

    H.test("Cosmetics pose catalog wrappers do not mutate authored data", function()
        local data = { item_type = "weapon_pose", parent = "sword", pose_index = 1, data = { anim_event = "pose" } }
        local catalog = Policy.build_catalog({ pose = data })
        local row = Policy.for_parent(catalog, "sword")[1]
        H.equal(row.data, data)
        H.equal(data.backend_id, nil)
        H.equal(row.backend_id, "cos_pose:pose")
    end)

    H.test("Cosmetics pose catalog validator certifies the clean contract only", function()
        local master = authored_master()
        local catalog = Policy.build_catalog(master)
        H.equal(Policy.validate_catalog(catalog, master), nil)
        -- Determinism across rebuilds: identical order, row for row.
        local rebuilt = Policy.build_catalog(master)
        for parent, rows in pairs(catalog) do
            for i = 1, #rows do
                H.equal(rebuilt[parent][i].ItemId, rows[i].ItemId)
            end
        end
        -- A dropped authored row is incomplete.
        local dropped = Policy.build_catalog(master)
        table.remove(dropped.es_2h_hammer, 2)
        H.truthy(Policy.validate_catalog(dropped, master))
        -- A cross-parent leak fails.
        local leaked = Policy.build_catalog(master)
        leaked.es_2h_hammer[#leaked.es_2h_hammer + 1] = {
            ItemId = "we_sword_dagger_pose_01",
            backend_id = "cos_pose:we_sword_dagger_pose_01",
            data = master.we_sword_dagger_pose_01,
        }
        H.truthy(Policy.validate_catalog(leaked, master))
        -- Unsorted rows fail.
        local unsorted = Policy.build_catalog(master)
        unsorted.es_2h_hammer[1], unsorted.es_2h_hammer[2] =
            unsorted.es_2h_hammer[2], unsorted.es_2h_hammer[1]
        H.truthy(Policy.validate_catalog(unsorted, master))
        -- A row that stops aliasing the master table (clone drift) fails.
        local cloned = Policy.build_catalog(master)
        cloned.es_2h_hammer[1] = {
            ItemId = "es_2h_hammer_pose_01",
            backend_id = "cos_pose:es_2h_hammer_pose_01",
            data = { item_type = "weapon_pose", parent = "es_2h_hammer",
                pose_index = 1, data = { anim_event = "anim_pose_01" } },
        }
        H.truthy(Policy.validate_catalog(cloned, master))
        -- An ownership write onto the master row fails.
        local stamped_master = authored_master()
        local stamped = Policy.build_catalog(stamped_master)
        stamped_master.es_2h_hammer_pose_01.backend_id = "leaked"
        H.truthy(Policy.validate_catalog(stamped, stamped_master))
    end)

    H.test("Cosmetics pose decision table keeps the three vanilla outcomes distinct", function()
        local rows = Policy.for_parent(
            Policy.build_catalog(authored_master()), "es_2h_hammer")
        H.equal(Policy.decide(true, true, rows), "authored")
        H.equal(Policy.decide(false, true, rows), "vanilla-setting-off")
        H.equal(Policy.decide(true, false, rows), "vanilla-official-realm")
        H.equal(Policy.decide(true, true, nil), "vanilla-unsupported-parent")
        -- Official realm wins over the setting in both orders.
        H.equal(Policy.decide(false, false, rows), "vanilla-official-realm")
        H.equal(Policy.decide(true, false, nil), "vanilla-official-realm")
    end)

    H.test("Cosmetics pose rebuild gate arms exactly once per flip", function()
        local holder = {}
        H.equal(Policy.rebuild_armed(holder, "k", true), true)
        H.equal(Policy.rebuild_armed(holder, "k", true), false)
        H.equal(Policy.rebuild_armed(holder, "k", false), true)
        H.equal(Policy.rebuild_armed(holder, "k", false), false)
        H.equal(Policy.rebuild_armed(nil, "k", true), false)
    end)

    -- Load the REAL production module against fixture globals and hand its
    -- captured SocialWheelUI hook bodies to the callback.
    local function isolated(master, callback)
        local saved = {
            get_mod = _G.get_mod,
            script_data = _G.script_data,
            ItemMasterList = _G.ItemMasterList,
            printf = _G.printf,
        }
        local state = { setting = true }
        local hooks, logs = {}, {}
        local mod = {
            _cos_weapon_pose_policy = dofile(policy_path),
            get = function(_, id)
                if id == "cos_unlock_weapon_poses" then return state.setting end
            end,
            hook = function(_, target, method, fn)
                if target ~= "SocialWheelUI" then
                    error("unexpected hook target: " .. tostring(target))
                end
                if hooks[method] then
                    error("duplicate hook on " .. tostring(method))
                end
                hooks[method] = fn
            end,
        }
        _G.get_mod = function(name)
            if name == "cosmetics_tweaker" then return mod end
        end
        _G.script_data = { ["eac-untrusted"] = true }
        _G.ItemMasterList = master
        _G.printf = function(fmt, ...)
            logs[#logs + 1] = string.format(fmt, ...)
        end
        local ok, module_or_err = pcall(dofile, module_path)
        local ok2, err2 = true, nil
        if ok then
            ok2, err2 = pcall(callback, module_or_err, hooks, state,
                _G.script_data, logs)
        end
        _G.get_mod = saved.get_mod
        _G.script_data = saved.script_data
        _G.ItemMasterList = saved.ItemMasterList
        _G.printf = saved.printf
        if not ok then error(module_or_err, 0) end
        if not ok2 then error(err2, 0) end
    end

    H.test("Cosmetics pose gather serves authored rows only when armed", function()
        isolated(authored_master(), function(module, hooks, state, script_data)
            local gather = hooks._gather_weapon_poses_by_parent_item
            H.equal(type(gather), "function")
            local vanilla_calls = 0
            local vanilla = function(_, parent_item)
                vanilla_calls = vanilla_calls + 1
                return "vanilla:" .. tostring(parent_item)
            end
            local wheel = {}
            -- Armed (setting on, untrusted realm): authored rows, vanilla untouched.
            local rows = gather(vanilla, wheel, "es_2h_hammer")
            H.equal(#rows, 2)
            H.equal(rows[1].ItemId, "es_2h_hammer_pose_01")
            H.equal(rows[2].ItemId, "es_2h_hammer_pose_02")
            H.equal(rows[1].data.data.anim_event, "anim_pose_01")
            H.equal(vanilla_calls, 0)
            H.equal(module.enabled(), true)
            -- Setting off: vanilla result even for an authored parent.
            state.setting = false
            H.equal(gather(vanilla, wheel, "es_2h_hammer"), "vanilla:es_2h_hammer")
            H.equal(vanilla_calls, 1)
            H.equal(module.enabled(), false)
            -- Official realm: vanilla result even with the setting on.
            state.setting = true
            script_data["eac-untrusted"] = false
            H.equal(gather(vanilla, wheel, "es_2h_hammer"), "vanilla:es_2h_hammer")
            H.equal(vanilla_calls, 2)
            H.equal(module.enabled(), false)
            local decision = module.decision_for("es_2h_hammer")
            H.equal(decision, "vanilla-official-realm")
        end)
    end)

    H.test("Cosmetics pose gather keeps unsupported parents vanilla with one bounded diagnostic", function()
        isolated(authored_master(), function(module, hooks, _, _, logs)
            local gather = hooks._gather_weapon_poses_by_parent_item
            local vanilla_calls = 0
            local vanilla = function(_, parent_item)
                vanilla_calls = vanilla_calls + 1
                return "vanilla:" .. tostring(parent_item)
            end
            local wheel = {}
            H.equal(gather(vanilla, wheel, "es_unsupported_weapon"),
                "vanilla:es_unsupported_weapon")
            H.equal(vanilla_calls, 1)
            H.equal(#logs, 1)
            H.truthy(logs[1]:find("[cos:485]", 1, true))
            H.truthy(logs[1]:find("es_unsupported_weapon", 1, true))
            -- Second miss on the same parent stays silent; vanilla still serves.
            H.equal(gather(vanilla, wheel, "es_unsupported_weapon"),
                "vanilla:es_unsupported_weapon")
            H.equal(vanilla_calls, 2)
            H.equal(#logs, 1)
            -- The bounded seam itself reports the dedup decision.
            H.equal(module.note_unsupported("es_unsupported_weapon"), false)
            H.equal(module.note_unsupported("es_other_weapon"), true)
            H.equal(#logs, 2)
        end)
    end)

    H.test("Cosmetics pose gather performs no ownership-table writes", function()
        local master = authored_master()
        local function snapshot(tbl)
            local keys = {}
            for k, v in pairs(tbl) do
                keys[k] = true
                if type(v) == "table" then
                    local inner = 0
                    for _ in pairs(v) do inner = inner + 1 end
                    keys[k] = inner
                end
            end
            return keys
        end
        local before = snapshot(master)
        isolated(master, function(_, hooks)
            local gather = hooks._gather_weapon_poses_by_parent_item
            local vanilla = function() return "vanilla" end
            gather(vanilla, {}, "es_2h_hammer")
            gather(vanilla, {}, "we_dual_wield_sword_dagger")
            gather(vanilla, {}, "es_unsupported_weapon")
        end)
        local after = snapshot(master)
        for key, count in pairs(before) do
            H.equal(after[key], count,
                "master row mutated by the gather path: " .. tostring(key))
        end
        for key in pairs(after) do
            H.truthy(before[key] ~= nil,
                "master list gained a key: " .. tostring(key))
        end
        H.equal(master.es_2h_hammer_pose_01.backend_id, nil)
    end)

    H.test("Cosmetics pose wheel rebuild arms exactly once per option change", function()
        isolated(authored_master(), function(_, hooks, state)
            local dirty = hooks._is_dirty
            H.equal(type(dirty), "function")
            local vanilla_calls = 0
            local vanilla = function() vanilla_calls = vanilla_calls + 1; return "vanilla-dirty" end
            local wheel = {}
            -- First observation arms the rebuild once, then defers to vanilla.
            H.equal(dirty(vanilla, wheel, "es_2h_hammer"), true)
            H.equal(vanilla_calls, 0)
            H.equal(dirty(vanilla, wheel, "es_2h_hammer"), "vanilla-dirty")
            H.equal(vanilla_calls, 1)
            -- Flip off: exactly one armed rebuild, then vanilla again.
            state.setting = false
            H.equal(dirty(vanilla, wheel, "es_2h_hammer"), true)
            H.equal(dirty(vanilla, wheel, "es_2h_hammer"), "vanilla-dirty")
            -- Flip back on: same one-shot contract.
            state.setting = true
            H.equal(dirty(vanilla, wheel, "es_2h_hammer"), true)
            H.equal(dirty(vanilla, wheel, "es_2h_hammer"), "vanilla-dirty")
            H.equal(vanilla_calls, 3)
        end)
    end)
end
