-- Pure lifecycle ledger for Cosmetics' asynchronous offhand package preloads.
-- Kept engine-free so the shared-handle late-callback race can be unit tested.
local M = {}

function M.new()
    local ledger = {
        active = true,
        generation = 1,
        owned = {},
        states = {},
        stats = {
            acquired = 0,
            ready = 0,
            invalidated = 0,
            late_callbacks_ignored = 0,
        },
    }

    function ledger:begin(path)
        if not self.active or self.owned[path] ~= nil then return nil end
        local token = self.generation
        self.owned[path] = token
        self.states[path] = "loading"
        self.stats.acquired = self.stats.acquired + 1
        return token
    end

    function ledger:complete(path, token)
        if not self.active or self.owned[path] ~= token then
            self.stats.late_callbacks_ignored = self.stats.late_callbacks_ignored + 1
            return false
        end
        if self.states[path] ~= "ready" then
            self.states[path] = "ready"
            self.stats.ready = self.stats.ready + 1
        end
        return true
    end

    function ledger:cancel(path, token)
        if self.owned[path] ~= token then return false end
        self.owned[path] = nil
        self.states[path] = nil
        self.stats.acquired = math.max(0, self.stats.acquired - 1)
        return true
    end

    function ledger:mark_resident(path)
        if self.active and self.states[path] == nil then self.states[path] = "resident" end
    end

    function ledger:release()
        if not self.active then return {} end
        self.active = false
        self.generation = self.generation + 1
        local paths = {}
        for path in pairs(self.owned) do paths[#paths + 1] = path end
        table.sort(paths)
        for _, path in ipairs(paths) do
            self.owned[path] = nil
            self.states[path] = nil
        end
        self.stats.invalidated = self.stats.invalidated + #paths
        return paths
    end

    return ledger
end

return M
