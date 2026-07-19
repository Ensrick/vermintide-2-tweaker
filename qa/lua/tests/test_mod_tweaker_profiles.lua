return function(H, repo_root)
    local path = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_profiles.lua"
    local Profiles = assert(loadfile(path))()
    local function store()
        local values = {}
        return { values = values,
            get = function(self, key) return self.values[key] end,
            set = function(self, key, value) self.values[key] = value end }
    end
    H.test("Mod Tweaker profiles default every tab to slot one", function()
        local s = store()
        H.equal(Profiles.get_active(s, "enemy_tweaker"), 1)
        H.equal(Profiles.set_active(s, "enemy_tweaker", 7), 7)
        H.equal(Profiles.get_active(s, "enemy_tweaker"), 7)
        H.equal(Profiles.set_active(s, "enemy_tweaker", 99), 10)
    end)
    H.test("Mod Tweaker stores one independent map per tab and slot", function()
        local s = store()
        Profiles.save(s, "enemy_tweaker", 1, { a = 1 })
        Profiles.save(s, "enemy_tweaker", 2, { a = 2 })
        Profiles.save(s, "gut_dev", 1, { a = 3 })
        H.deep_equal(Profiles.load(s, "enemy_tweaker", 1), { a = 1 })
        H.deep_equal(Profiles.load(s, "enemy_tweaker", 2), { a = 2 })
        H.deep_equal(Profiles.load(s, "gut_dev", 1), { a = 3 })
    end)
    H.test("Mod Tweaker owner-qualified profile members round trip", function()
        local key = Profiles.member_key("cosmetics:tweaker", "shared::setting")
        local owner, setting = Profiles.split_member_key(key)
        H.equal(owner, "cosmetics:tweaker")
        H.equal(setting, "shared::setting")
        H.equal(Profiles.split_member_key("broken"), nil)
    end)
    H.test("Mod Tweaker profile loads return owned maps", function()
        local s = store()
        Profiles.save(s, "enemy_tweaker", 1, { a = 1 })
        local loaded = Profiles.load(s, "enemy_tweaker", 1)
        loaded.a = 9
        H.equal(Profiles.load(s, "enemy_tweaker", 1).a, 1)
    end)
    H.test("Mod Tweaker profile upgrades inherit only missing defaults", function()
        local start_shop = Profiles.member_key("ct_dev", "ct_buy_starting_boons")
        local old_setting = Profiles.member_key("ct_dev", "starting_coins")
        local saved = { [old_setting] = 250 }
        local defaults = { [old_setting] = 0, [start_shop] = false }
        local merged, additions, count = Profiles.reconcile(saved, defaults)
        H.equal(count, 1)
        H.equal(merged[old_setting], 250)
        H.equal(merged[start_shop], false)
        H.equal(additions[start_shop], false)
        H.equal(saved[start_shop], nil, "reconcile must not mutate the persisted source map")

        saved[start_shop] = true
        merged, additions, count = Profiles.reconcile(saved, defaults)
        H.equal(count, 0)
        H.equal(merged[start_shop], true, "an explicit opt-in must survive migration")
        H.equal(next(additions), nil)
    end)
    H.test("CT starting shop remains an explicit opt-in at the definition", function()
        local file = assert(io.open(repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev_data.lua", "rb"))
        local source = file:read("*a")
        file:close()
        local start = assert(string.find(source,
            'setting_id = "ct_buy_starting_boons"', 1, true))
        local block = string.sub(source, start, start + 220)
        H.truthy(string.find(block, "default_value = false", 1, true))
    end)
    H.test("CT trial-cost migration covers every persisted dev profile", function()
        for _, spec in ipairs({
            { "gui_tweaker_dev", "gui_tweaker_dev" },
        }) do
            local profiles = assert(loadfile(repo_root .. "/" .. spec[1]
                .. "/scripts/mods/" .. spec[2] .. "/_mod_tweaker_profiles.lua"))()
            local s = store()
            local disabled = profiles.member_key("ct_dev", "cot_cost_enabled")
            local enabled = profiles.member_key("ct", "cot_cost_enabled")
            local dev_amount = profiles.member_key("ct_dev", "cot_cost_amount")
            local stable_amount = profiles.member_key("ct", "cot_cost_amount")
            profiles.save(s, "ct_dev", 1, { [disabled] = false, [dev_amount] = 100 })
            profiles.save(s, "ct_dev", 2, { [disabled] = true, [dev_amount] = 112 })
            profiles.save(s, "ct", 3, { [enabled] = true, unrelated = "kept" })
            profiles.save(s, "gut_dev", 4, { untouched = 9 })

            local ok, changed = profiles.migrate_all(s)
            H.equal(ok, true)
            H.equal(changed, 3)
            local slot1 = profiles.load(s, "ct_dev", 1)
            local slot2 = profiles.load(s, "ct_dev", 2)
            local slot3 = profiles.load(s, "ct", 3)
            H.equal(slot1[disabled], nil)
            H.equal(slot1[dev_amount], 0)
            H.equal(slot2[disabled], nil)
            H.equal(slot2[dev_amount], 100)
            H.equal(slot3[enabled], nil)
            H.equal(slot3[stable_amount], 100)
            H.equal(slot3.unrelated, "kept")
            H.deep_equal(profiles.load(s, "gut_dev", 4), { untouched = 9 })
            ok, changed = profiles.migrate_all(s)
            H.equal(ok, true)
            H.equal(changed, 0, "the bounded migration must be idempotent")
        end
    end)
    H.test("CT trial-cost migration retries after a failed store operation", function()
        local profiles = Profiles
        local s = store()
        local legacy = profiles.member_key("ct_dev", "cot_cost_enabled")
        local amount = profiles.member_key("ct_dev", "cot_cost_amount")
        profiles.save(s, "ct_dev", 1, { [legacy] = false, [amount] = 100 })
        local original_set = s.set
        local failed = false
        s.set = function(self, key, value)
            if not failed and string.find(key, "mt_profile::ct_dev::1", 1, true) then
                failed = true
                error("injected persistence failure")
            end
            return original_set(self, key, value)
        end
        local ok, changed, err = profiles.migrate_all(s)
        H.equal(ok, false)
        H.equal(changed, 0)
        H.truthy(string.find(err, "injected persistence failure", 1, true))
        s.set = original_set
        ok, changed = profiles.migrate_all(s)
        H.equal(ok, true)
        H.equal(changed, 1)
        H.equal(profiles.load(s, "ct_dev", 1)[amount], 0)
    end)
    H.test("profile runtime reports owner apply failures before persistence", function()
        for _, spec in ipairs({
            { "gui_tweaker_dev", "gui_tweaker_dev" },
        }) do
            local root = repo_root .. "/" .. spec[1] .. "/scripts/mods/" .. spec[2] .. "/"
            local profiles = assert(loadfile(root .. "_mod_tweaker_profiles.lua"))()
            local runtime = assert(loadfile(root .. "_mod_tweaker_profile_runtime.lua"))()
            local member = profiles.member_key("ct_dev", "new_default")
            local category = { _owners = { ct_dev = {} } }
            local owner = function(_, setting_id)
                if setting_id == "new_default" then return category._owners.ct_dev, "ct_dev" end
            end
            local success_tx = { commit = function(_, pending)
                return pending.new_default ~= nil and 1 or 0, true
            end }
            local merged, additions, added, applied_ok, applied, failures =
                runtime.reconcile_and_apply({
                    profiles = profiles, transactions = success_tx,
                    values = {}, defaults = { [member] = false },
                    category = category, owner = owner, set_one = function() end,
                })
            H.equal(merged[member], false)
            H.equal(additions[member], false)
            H.equal(added, 1)
            H.equal(applied_ok, true)
            H.equal(applied, 1)
            H.equal(failures, 0)

            local failed_tx = { commit = function() return 1, true, "callback failed" end }
            local _, _, _, failed_ok, failed_applied, failed_count, failed_err =
                runtime.reconcile_and_apply({
                    profiles = profiles, transactions = failed_tx,
                    values = {}, defaults = { [member] = false },
                    category = category, owner = owner, set_one = function() end,
                })
            H.equal(failed_ok, false)
            H.equal(failed_applied, 1)
            H.equal(failed_count, 1)
            H.equal(failed_err, "callback failed")
        end
    end)
    H.test("both dev Mod Tweaker presentations apply defaults before saving", function()
        for _, spec in ipairs({
            { "gui_tweaker_dev", "gui_tweaker_dev" },
        }) do
          for _, name in ipairs({ "_mod_tweaker_view.lua", "_mod_tweaker_state.lua" }) do
            local file = assert(io.open(repo_root
                .. "/" .. spec[1] .. "/scripts/mods/" .. spec[2] .. "/" .. name, "rb"))
            local source = file:read("*a")
            file:close()
            H.truthy(string.find(source, "function ", 1, true))
            H.truthy(string.find(source, ":_switch_profile(slot)", 1, true))
            H.truthy(string.find(source, "self:apply_pending(category)", 1, true))
            H.truthy(string.find(source, "profiles.member_key(owner_id, sid)", 1, true))
            H.truthy(string.find(source, "profile_runtime.reconcile_and_apply", 1, true))
            H.truthy(string.find(source,
                "profile_runtime.migrate(profiles, mod", 1, true))
            local switch_start = assert(string.find(source, ":_switch_profile(slot)", 1, true))
            local switch_end = assert(string.find(source, "\nfunction ",
                switch_start + 1, true))
            local block = string.sub(source, switch_start, switch_end - 1)
            local apply_at = assert(string.find(block,
                "profile_runtime.reconcile_and_apply", 1, true))
            local save_at = assert(string.find(block,
                "if added > 0 then profiles.save(mod, tab_id, slot, values) end", 1, true))
            local active_at = assert(string.find(block,
                "profiles.set_active(mod, tab_id, slot)", 1, true))
            H.truthy(apply_at < save_at,
                "reconciled defaults must apply before the target profile is saved")
            H.truthy(save_at < active_at,
                "the target profile must be durable before it becomes active")
            H.truthy(string.find(block,
                "reconciled_additions[member] == nil", 1, true),
                "reconciled defaults must not be applied twice")
          end
        end
    end)
    H.test("standalone search and profile transactions coexist", function()
        local root = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/"
        local file = assert(io.open(root .. "_mod_tweaker_view.lua", "rb"))
        local source = file:read("*a")
        file:close()
        file = assert(io.open(root .. "_mod_tweaker_view_interaction.lua", "rb"))
        source = source .. file:read("*a")
        file:close()
        H.truthy(string.find(source, "_mod_tweaker_search", 1, true))
        H.truthy(string.find(source, "_mod_tweaker_profiles", 1, true))
        H.truthy(string.find(source, "self:_switch_profile(i)", 1, true))
        H.truthy(string.find(source, "self._search_tx", 1, true))
    end)
end
