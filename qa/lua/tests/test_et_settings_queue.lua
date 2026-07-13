return function(H, repo_root)
    local module_path = repo_root
        .. "/enemy_tweaker/scripts/mods/enemy_tweaker/_et_settings_queue.lua"
    local SettingsQueue = assert(loadfile(module_path))()

    H.test("Enemy Tweaker coalesces a bulk reset into one apply", function()
        local applied = {}
        local queue = SettingsQueue.new(function(ids, latest)
            applied[#applied + 1] = { ids = ids, latest = latest }
        end)

        queue.enqueue_many({ "third", "first", "second", "first" })
        H.equal(queue.count(), 3)
        H.equal(#applied, 0)
        H.equal(queue.drain(), 3)
        H.equal(#applied, 1)
        H.deep_equal(applied[1], {
            ids = { "first", "second", "third" },
            latest = "first",
        })
        H.equal(queue.drain(), 0)
        H.equal(#applied, 1)
    end)

    H.test("Enemy Tweaker single changes apply on the next drain", function()
        local calls = 0
        local queue = SettingsQueue.new(function(ids, latest)
            calls = calls + 1
            H.deep_equal(ids, { "roaming_size_multiplier" })
            H.equal(latest, "roaming_size_multiplier")
        end)

        queue.enqueue("roaming_size_multiplier")
        H.equal(calls, 0)
        queue.drain()
        H.equal(calls, 1)
    end)

    H.test("Enemy Tweaker bounds the observed 249-setting reset", function()
        local calls, applied_count = 0, 0
        local queue = SettingsQueue.new(function(ids)
            calls = calls + 1
            applied_count = #ids
        end)
        for i = 1, 249 do queue.enqueue("setting_" .. tostring(i)) end

        H.equal(calls, 0)
        H.equal(queue.drain(), 249)
        H.equal(calls, 1)
        H.equal(applied_count, 249)
    end)

    H.test("Enemy Tweaker queue clear and reentrant apply are safe", function()
        local calls = 0
        local queue
        queue = SettingsQueue.new(function()
            calls = calls + 1
            if calls == 1 then queue.enqueue("queued_during_apply") end
        end)

        queue.enqueue("discard_me")
        queue.clear()
        H.equal(queue.drain(), 0)
        queue.enqueue("first")
        H.equal(queue.drain(), 1)
        H.equal(queue.count(), 1)
        H.equal(queue.drain(), 1)
        H.equal(calls, 2)
    end)
end
