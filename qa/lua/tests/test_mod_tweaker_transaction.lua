return function(H, repo_root)
    local module_path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_transaction.lua"
    local Transaction = assert(loadfile(module_path))()
    local DefaultReset = assert(loadfile(repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_default_reset.lua"))()

    H.test("Mod Tweaker official reseed intent is scoped to WT and Cosmetics", function()
        H.equal(DefaultReset.affects_loadouts({ mod_id = "wt_dev" }), true)
        H.equal(DefaultReset.affects_loadouts({ mod_id = "wt" }), true)
        H.equal(DefaultReset.affects_loadouts({ mod_id = "cosmetics_tweaker" }), true)
        H.equal(DefaultReset.affects_loadouts({ mod_id = "cim_dev" }), false)
        H.equal(DefaultReset.affects_loadouts({
            mod_id = "gut_equipment",
            _owner_mod_ids = { "cim_dev", "character_weapon_variants", "wt_dev" },
        }), true)
        H.equal(DefaultReset.affects_loadouts({
            mod_id = "gut_equipment",
            _owner_mod_ids = { "cim_dev", "character_weapon_variants" },
        }), false)
    end)

    H.test("Mod Tweaker official reseed survives failure and completes once", function()
        local view = {}
        local category = { mod_id = "gut_equipment", _owner_mod_ids = { "wt_dev" } }
        H.equal(DefaultReset.arm(view, category), true)
        H.equal(DefaultReset.is_armed(view, category), true)

        local attempted, complete, err = DefaultReset.finish(view, category, false, function()
            error("must not run before settings complete")
        end)
        H.equal(attempted, true)
        H.equal(complete, false)
        H.equal(err, "settings transaction incomplete")
        H.equal(DefaultReset.is_armed(view, category), true)

        attempted, complete, err = DefaultReset.finish(view, category, true, function()
            return false, "planted reset rejection"
        end)
        H.equal(attempted, true)
        H.equal(complete, false)
        H.equal(err, "planted reset rejection")
        H.equal(DefaultReset.is_armed(view, category), true)

        local calls, source = 0
        attempted, complete, err = DefaultReset.finish(view, category, true, function(reason)
            calls = calls + 1
            source = reason
            return true
        end)
        H.equal(attempted, true)
        H.equal(complete, true)
        H.equal(err, nil)
        H.equal(calls, 1)
        H.equal(source, "mod_tweaker_default")
        H.equal(DefaultReset.is_armed(view, category), false)
        H.equal(DefaultReset.finish(view, category, true, function() calls = calls + 1 end), false)
        H.equal(calls, 1)
    end)

    H.test("Mod Tweaker batches opt-in owner notifications", function()
        local writes, batches = {}, {}
        local owner = {
            set = function(self, id, value, notify)
                writes[#writes + 1] = { id, value, notify }
            end,
            on_settings_batch_changed = function(ids)
                batches[#batches + 1] = ids
            end,
        }
        local fallback = 0
        local count, batched, err, complete = Transaction.commit({}, { z = 3, a = 1, m = 2 },
            function() return owner end,
            function() fallback = fallback + 1 end)

        H.equal(count, 3)
        H.equal(batched, true)
        H.equal(err, nil)
        H.equal(complete, true)
        H.equal(fallback, 0)
        H.equal(#writes, 3)
        for i = 1, #writes do H.equal(writes[i][3], false) end
        H.equal(#batches, 1)
        H.deep_equal(batches[1], { "a", "m", "z" })
    end)

    H.test("Mod Tweaker preserves per-setting fallback semantics", function()
        local owner = { set = function() end }
        local notified = {}
        local count, batched, err, complete = Transaction.commit({}, { first = 1, second = 2 },
            function() return owner end,
            function(_, id, value) notified[id] = value end)

        H.equal(count, 2)
        H.equal(batched, false)
        H.equal(err, nil)
        H.equal(complete, true)
        H.deep_equal(notified, { first = 1, second = 2 })
    end)

    H.test("Mod Tweaker contains an opted-in batch callback failure", function()
        local owner = {
            set = function() end,
            on_settings_batch_changed = function() error("planted batch failure") end,
        }
        local ok, count, batched, err, complete = pcall(Transaction.commit, {}, { one = 1 },
            function() return owner end,
            function() error("fallback must not run") end)

        H.equal(ok, true)
        H.equal(count, 1)
        H.equal(batched, true)
        H.equal(complete, false)
        H.truthy(type(err) == "string" and string.find(err, "planted batch failure", 1, true))
    end)

    H.test("Mod Tweaker reports a partial silent-write failure as retryable", function()
        local writes = 0
        local owner = {
            set = function()
                writes = writes + 1
                if writes == 2 then error("planted write failure") end
            end,
            on_settings_batch_changed = function()
                error("callback must not run after a write failure")
            end,
        }
        local count, batched, err, complete = Transaction.commit(
            {}, { a = 1, b = 2, c = 3 },
            function() return owner end,
            function() error("fallback must not run") end)

        H.equal(count, 1)
        H.equal(batched, true)
        H.equal(complete, false)
        H.truthy(type(err) == "string"
            and string.find(err, "planted write failure", 1, true))
    end)

    H.test("Mod Tweaker contains a legacy owner write failure", function()
        local calls = 0
        local count, batched, err, complete = Transaction.commit(
            {}, { one = 1, two = 2 },
            function() return { set = function() end } end,
            function()
                calls = calls + 1
                error("planted legacy failure")
            end)

        H.equal(calls, 1)
        H.equal(count, 0)
        H.equal(batched, false)
        H.equal(complete, false)
        H.truthy(type(err) == "string"
            and string.find(err, "planted legacy failure", 1, true))
    end)

    H.test("Equipment owner commits stay bounded by owner count", function()
        local writes, notifications = 0, 0
        local pending_by_owner = {
            cosmetics_tweaker = { a = 1, b = 2, c = 3 },
            cim_dev = { d = 4, e = 5 },
            wt = { f = 6, g = 7, h = 8, i = 9 },
            character_weapon_variants = { j = 10 },
        }
        for _, pending in pairs(pending_by_owner) do
            local owner = {
                set = function() writes = writes + 1 end,
                on_settings_batch_changed = function() notifications = notifications + 1 end,
            }
            local count, batched, err, complete = Transaction.commit({}, pending,
                function() return owner end,
                function() error("Equipment owners must not use legacy notify") end)
            H.equal(count, (function()
                local n = 0
                for _ in pairs(pending) do n = n + 1 end
                return n
            end)())
            H.equal(batched, true)
            H.equal(err, nil)
            H.equal(complete, true)
        end
        H.equal(writes, 10, "every value must still persist")
        H.equal(notifications, 4,
            "callback/application work must be bounded by Equipment owner count")
    end)

    H.test("Every in-flight Equipment owner opts into the bounded transaction", function()
        local paths = {
            "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_settings_runtime.lua",
            "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_settings_runtime.lua",
            "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_settings_runtime.lua",
            "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_settings_runtime.lua",
            "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua",
        }
        for i = 1, #paths do
            local file = assert(io.open(repo_root .. paths[i], "rb"))
            local source = file:read("*a")
            file:close()
            H.truthy(source:find("on_settings_batch_changed", 1, true),
                paths[i] .. " must implement the owner batch callback")
        end
    end)

    H.test("CIM dev coalesces settings while stable fallback remains bounded", function()
        local dev_path =
            "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_settings_runtime.lua"
        local Runtime = assert(loadfile(repo_root .. dev_path))()
        local mod, applies, records = {}, 0, 0
        Runtime.install(mod, function() applies = applies + 1 end,
            function() records = records + 1 end)
        mod.on_setting_changed("unrelated")
        mod.on_setting_changed("movespeed_2pct_mode")
        mod.on_settings_batch_changed({
            "unrelated", "movespeed_2pct_mode", "movespeed_2pct_mode",
        })
        H.equal(applies, 2, "CIM dev applies once per completion path")
        H.equal(records, 1, "CIM dev records one batch completion")

        -- Stable split streams do not receive in-flight fixes. Its legacy
        -- callback is nevertheless bounded: only one exact setting can invoke
        -- the sole heavyweight re-apply during a per-setting fallback reset.
        local stable_path =
            "/crafting_in_modded/scripts/mods/crafting_in_modded/crafting_in_modded.lua"
        local file = assert(io.open(repo_root .. stable_path, "rb"))
        local stable = file:read("*a")
        file:close()
        H.truthy(stable:find(
            'mod%.on_setting_changed = function%(setting_id%)%s+if setting_id == "movespeed_2pct_mode" then%s+_patch_movespeed_buff%(%)%s+end%s+end'
        ), "stable CIM fallback must keep heavyweight work behind one exact setting")
    end)

    H.test("Both Mod Tweaker views retain failed owner buffers", function()
        local paths = {
            "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_view.lua",
            "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_state.lua",
        }
        for i = 1, #paths do
            local file = assert(io.open(repo_root .. paths[i], "rb"))
            local source = file:read("*a")
            file:close()
            H.truthy(source:find("if complete then", 1, true)
                and source:find("self._pending[mid] = {}", 1, true),
                paths[i] .. " clears an owner only after completion")
            H.truthy(source:find(
                "if not failed then self:_profile_capture(category) end",
                1, true), paths[i] .. " cannot capture a partial Equipment profile")
            H.truthy(source:find(
                "if complete then self._pending[key] = {} end",
                1, true), paths[i] .. " retains a failed single-owner buffer")
            H.truthy(source:find(
                "if complete then self:_profile_capture(category) end",
                1, true), paths[i] .. " cannot capture a failed single-owner profile")
            H.truthy(source:find(
                "self:apply_pending(category)\n        if self:_active_category_dirty() then",
                1, true), paths[i] .. " aborts a profile switch after an incomplete commit")
            H.truthy(source:find(
                "pending transaction incomplete",
                1, true), paths[i] .. " diagnoses a deferred profile switch once")
            H.truthy(source:find("default_reset.arm(self, category)", 1, true),
                paths[i] .. " does not retain DEFAULT's loadout reseed intent")
            H.truthy(source:find("default_reset.is_armed(self, cat)", 1, true),
                paths[i] .. " cannot enable Apply for a reseed-only transaction")
            H.truthy(source:find("default_reset.finish(", 1, true),
                paths[i] .. " never completes the official reseed transaction")
            H.truthy(source:find("default_reset.clear(self)", 1, true),
                paths[i] .. " can leak a discarded reseed intent across view sessions")
        end
    end)
end
