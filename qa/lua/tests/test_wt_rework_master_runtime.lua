return function(H, repo_root)
    local policy_path = repo_root
        .. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_rework_master_policy.lua"
    local runtime_path = repo_root
        .. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_rework_master_runtime.lua"
    local Policy = assert(loadfile(policy_path))()
    local Runtime = assert(loadfile(runtime_path))()

    local function fixture()
        local values, writes, applies = {}, {}, 0
        local mod = {
            get = function(_, id) return values[id] end,
            set = function(_, id, value, notify)
                values[id] = value
                writes[#writes + 1] = { id = id, value = value, notify = notify }
            end,
            warning = function() end,
        }
        local runtime = Runtime.new(mod, Policy, function() applies = applies + 1 end)
        return runtime, values, writes, function() return applies end
    end

    H.test("WT #1002 complete rework snapshot preserves leaf values", function()
        local runtime, values, writes, applies = fixture()
        local changed = { Policy.MASTER_ID }
        values[Policy.MASTER_ID] = false
        for i = 1, #Policy.LEAF_IDS do
            local id = Policy.LEAF_IDS[i]
            changed[#changed + 1] = id
            values[id] = i == 1
        end

        H.equal(runtime:prepare_batch(changed), true)
        H.equal(values[Policy.LEAF_IDS[1]], true)
        H.equal(values[Policy.LEAF_IDS[2]], false)
        H.equal(values[Policy.MASTER_ID], false)
        H.equal(#writes, 0)
        H.equal(applies(), 0, "owner performs the one final live apply")
    end)

    H.test("WT #1002 lone rework master cascades without duplicate live apply", function()
        local runtime, values, writes, applies = fixture()
        values[Policy.MASTER_ID] = true
        for i = 1, #Policy.LEAF_IDS do values[Policy.LEAF_IDS[i]] = false end

        H.equal(runtime:prepare_batch({ Policy.MASTER_ID }), true)
        for i = 1, #Policy.LEAF_IDS do
            H.equal(values[Policy.LEAF_IDS[i]], true)
        end
        H.equal(values[Policy.MASTER_ID], true)
        H.equal(#writes, #Policy.LEAF_IDS)
        for i = 1, #writes do H.equal(writes[i].notify, false) end
        H.equal(applies(), 0, "master reconciliation must defer the final apply")
    end)
end
