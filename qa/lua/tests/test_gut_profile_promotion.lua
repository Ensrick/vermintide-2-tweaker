return function(H, repo_root)
    local root = repo_root .. "/gui_tweaker/scripts/mods/gui_tweaker/"
    local Profiles = assert(loadfile(root .. "_mod_tweaker_profiles.lua"))()
    local Runtime = assert(loadfile(root .. "_mod_tweaker_profile_runtime.lua"))()

    local function store()
        local values = {}
        return {
            values = values,
            get = function(self, key) return self.values[key] end,
            set = function(self, key, value) self.values[key] = value end,
        }
    end

    H.test("stable GUT migrates all stored CT trial-cost profiles", function()
        local s = store()
        local enabled = Profiles.member_key("ct_dev", "cot_cost_enabled")
        local amount = Profiles.member_key("ct_dev", "cot_cost_amount")
        Profiles.save(s, "ct_dev", 1, { [enabled] = false, [amount] = 100 })
        Profiles.save(s, "ct_dev", 10, { [enabled] = true, [amount] = 112 })
        local ok, changed = Profiles.migrate_all(s)
        H.equal(ok, true)
        H.equal(changed, 2)
        H.equal(Profiles.load(s, "ct_dev", 1)[amount], 0)
        H.equal(Profiles.load(s, "ct_dev", 10)[amount], 100)
        ok, changed = Profiles.migrate_all(s)
        H.equal(ok, true)
        H.equal(changed, 0)
    end)

    H.test("stable GUT profile apply failure remains uncommitted", function()
        local member = Profiles.member_key("ct_dev", "new_default")
        local category = { _owners = { ct_dev = {} } }
        local owner = function(_, setting_id)
            if setting_id == "new_default" then return category._owners.ct_dev, "ct_dev" end
        end
        local transactions = {
            commit = function() return 1, true, "injected callback failure" end,
        }
        local _, _, added, ok, applied, failures, err = Runtime.reconcile_and_apply({
            profiles = Profiles,
            transactions = transactions,
            values = {},
            defaults = { [member] = false },
            category = category,
            owner = owner,
            set_one = function() end,
        })
        H.equal(added, 1)
        H.equal(ok, false)
        H.equal(applied, 1)
        H.equal(failures, 1)
        H.equal(err, "injected callback failure")
    end)
end
