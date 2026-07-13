return function(H, repo_root)
    local module_path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_transaction.lua"
    local Transaction = assert(loadfile(module_path))()

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
        local count, batched = Transaction.commit({}, { z = 3, a = 1, m = 2 },
            function() return owner end,
            function() fallback = fallback + 1 end)

        H.equal(count, 3)
        H.equal(batched, true)
        H.equal(fallback, 0)
        H.equal(#writes, 3)
        for i = 1, #writes do H.equal(writes[i][3], false) end
        H.equal(#batches, 1)
        H.deep_equal(batches[1], { "a", "m", "z" })
    end)

    H.test("Mod Tweaker preserves per-setting fallback semantics", function()
        local owner = { set = function() end }
        local notified = {}
        local count, batched = Transaction.commit({}, { first = 1, second = 2 },
            function() return owner end,
            function(_, id, value) notified[id] = value end)

        H.equal(count, 2)
        H.equal(batched, false)
        H.deep_equal(notified, { first = 1, second = 2 })
    end)

    H.test("Mod Tweaker contains an opted-in batch callback failure", function()
        local owner = {
            set = function() end,
            on_settings_batch_changed = function() error("planted batch failure") end,
        }
        local ok, count, batched, err = pcall(Transaction.commit, {}, { one = 1 },
            function() return owner end,
            function() error("fallback must not run") end)

        H.equal(ok, true)
        H.equal(count, 1)
        H.equal(batched, true)
        H.truthy(type(err) == "string" and string.find(err, "planted batch failure", 1, true))
    end)
end
