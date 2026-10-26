-- #942 injected VMF adapter; protocol math/replay state remains in its owner.
-- Callback sender is the cooperative VMF identity, not cryptographic identity.
local M = { CHANNEL = "wt_fire_sword_heat_config_v1" }
local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local function finite(n) return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge end
local function peer(id) return type(id) == "string" and #id > 0 and #id <= 64 and id:match("^[%w_.:%-]+$") ~= nil end

-- Lossless 128-bit GUID -> 22 base64url characters. Never truncate/hash a GUID.
function M.epoch(guid)
    if type(guid) ~= "string" then return nil end
    if guid:sub(1,1) == "{" and guid:sub(-1) == "}" then guid = guid:sub(2,-2) end
    if #guid == 36 then
        if not guid:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") then return nil end
        guid = guid:gsub("%-", "")
    end
    if #guid ~= 32 or not guid:match("^%x+$") then return nil end
    local out, value, bits = {}, 0, 0
    for i = 1, 32 do
        value, bits = value * 16 + tonumber(guid:sub(i,i),16), bits + 4
        while bits >= 6 do
            bits = bits - 6
            local digit = math.floor(value / 2^bits)
            out[#out+1] = ALPHABET:sub(digit+1,digit+1)
            value = value % 2^bits
        end
    end
    if bits > 0 then local digit = value * 2^(6-bits); out[#out+1] = ALPHABET:sub(digit+1,digit+1) end
    return table.concat(out)
end

function M.new(deps)
    for _, key in ipairs({ "humans", "local_peer", "read_config", "send", "changed", "committed" }) do
        assert(type(deps[key]) == "function", "#942 transport dependency missing: " .. key)
    end
    local P = assert(deps.protocol, "#942 config protocol missing")
    local self = { clock = 0, pending = {}, poisoned = false }
    local protocol
    local function roster()
        local humans, me = deps.humans(), deps.local_peer()
        if type(humans) ~= "table" or not peer(me) then return {}, false end
        local others, count, found_local = {}, 0, false
        for _, player in pairs(humans) do
            local id = type(player) == "table" and player.peer_id
            if not peer(id) then return {}, false end
            if id == me then found_local = true
            elseif not others[id] then others[id], count = true, count+1 end
        end
        for id in pairs(self.pending) do
            if others[id] then self.pending[id] = nil
            elseif not others[id] then others[id], count = true, count+1 end
        end
        if count > P.MAX_PEERS then return {}, false end
        return others, found_local
    end
    protocol = P.new({ epoch = deps.epoch, read_config = deps.read_config,
        read_peers = roster,
        send = function(id, packet)
            assert(deps.committed() == true and not self.poisoned, "#942 uncommitted send")
            return deps.send(M.CHANNEL, id, unpack(packet, 1, 13))
        end,
        changed = function(value) deps.changed(value) end,
    })
    self.protocol = protocol
    function self:poison()
        self.poisoned = true
        protocol:allows(nil, -1)
        deps.changed(false)
    end
    function self:tick(dt)
        if self.poisoned or deps.committed() ~= true then return false end
        if not finite(dt) or dt < 0 or not finite(self.clock + dt) then self:poison(); return false end
        self.clock = self.clock + dt
        return protocol:tick(self.clock)
    end
    function self:settings_changed()
        if self.poisoned or deps.committed() ~= true then return false end
        return protocol:settings_changed(self.clock)
    end
    function self:allows(config)
        return not self.poisoned and deps.committed() == true
            and protocol:allows(config, self.clock) == true
    end
    function self:receive(sender, ...)
        if self.poisoned or deps.committed() ~= true then return false end
        if select("#", ...) ~= 13 or not peer(sender) then return false end
        return protocol:receive(sender, {...}, self.clock)
    end
    function self:require_peer(id)
        if not peer(id) then self:poison(); return false end
        local ok, me = pcall(deps.local_peer)
        if not ok or not peer(me) then self:poison(); return false end
        if id == me then return true end
        if not self.pending[id] then
            local count = 0; for _ in pairs(self.pending) do count = count + 1 end
            if count >= P.MAX_PEERS then self:poison(); return false end
            self.pending[id] = true
        end
        return self:settings_changed()
    end
    function self:disconnect(id)
        self.pending[id] = nil
        if deps.committed() == true and not self.poisoned then return protocol:disconnect(id, self.clock) end
        return false
    end
    return self
end
return M
