-- _et_settings_queue.lua - coalesce synchronous setting-change bursts.
--
-- VMF fires one synchronous callback for every notified write. This tiny,
-- engine-free queue records distinct setting ids and drains them once on the
-- next update, bounding expensive recompute work to one pass per frame.
--
-- Owned by: enemy_tweaker.lua manifest. Consumed via: mod._et.SettingsQueue.

local SettingsQueue = {}

function SettingsQueue.new(apply)
    local pending = {}
    local count = 0
    local latest

    local queue = {}

    function queue.enqueue(setting_id)
        local key = tostring(setting_id or "<unknown>")
        if not pending[key] then
            pending[key] = true
            count = count + 1
        end
        latest = key
    end

    function queue.enqueue_many(setting_ids)
        if type(setting_ids) ~= "table" then
            queue.enqueue(setting_ids)
            return
        end
        for i = 1, #setting_ids do queue.enqueue(setting_ids[i]) end
    end

    function queue.drain()
        if count == 0 then return 0 end
        local ids = {}
        for setting_id in pairs(pending) do ids[#ids + 1] = setting_id end
        table.sort(ids)
        local drained_count = count
        local drained_latest = latest
        pending = {}
        count = 0
        latest = nil
        apply(ids, drained_latest)
        return drained_count
    end

    function queue.clear()
        pending = {}
        count = 0
        latest = nil
    end

    function queue.count() return count end

    return queue
end

return SettingsQueue
