-- Optional native-source proof only; no engine or VMF implementation is copied.
-- Loads the complete source helper in a private, fixed-forward geometry boundary.
-- Owned by the offline Mace movement suite, never loaded by a deployed mod.
local M = {}
local RELATIVE = "/scripts/unit_extensions/default_player_unit/states/player_character_state_helper.lua"
function M.available(native_root)
    local file = io.open(native_root .. RELATIVE, "rb")
    if not file then return false end
    file:close()
    return true
end
function M.new(H, native_root, f)
    local n, Vec = { calls = 0, rotations = 0 }, {}
    Vec.__index = Vec
    local function vec(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, Vec) end
    function Vec.__add(a, b) return vec(a.x + b.x, a.y + b.y, a.z + b.z) end
    function Vec.__mul(a, b)
        if type(a) == "number" then a, b = b, a end
        return vec(a.x * b, a.y * b, a.z * b)
    end
    function Vec.__unm(a) return vec(-a.x, -a.y, -a.z) end
    local V = setmetatable({}, { __call = function(_, ...) return vec(...) end })
    function V.length(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
    function V.normalize(a)
        local length = V.length(a)
        return length == 0 and vec() or vec(a.x / length, a.y / length, a.z / length)
    end
    function V.flat(a) return vec(a.x, a.y, 0) end
    function V.dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
    function V.set_y(a, value) a.y = value end
    function V.up() return vec(0, 0, 1) end
    function V.right() return vec(1, 0, 0) end
    function V.forward() return vec(0, 1, 0) end
    -- Deliberately only a fixed forward-facing coordinate basis, not a renderer
    -- or quaternion simulator. The actual native movement math runs below.
    local rotation = {}
    local Q = { forward = V.forward, look = function() return rotation end,
        rotate = function(_, value) return vec(value.x, value.y, value.z) end }
    n.settings = { move_speed = 5, backward_move_scale = 0.5, player_speed_scale = 1 }
    n.previous, n.move = vec(), vec(0, 1, 0)
    f.first.current_rotation = function(self)
        H.equal(self, f.first); n.rotations = n.rotations + 1; return rotation
    end
    f.input.get = function(self, key)
        H.equal(self, f.input)
        if key == "move" then return n.move end
        if key == "move_controller" then return vec() end
        error("unexpected native movement input: " .. tostring(key))
    end
    f.locomotion.current_velocity = function(self) H.equal(self, f.locomotion); return n.previous end
    f.locomotion.set_wanted_velocity = function(self, value)
        H.equal(self, f.locomotion); n.calls = n.calls + 1; n.wanted = value
    end
    local env = setmetatable({ CharacterStateHelper = {}, Vector3 = V, Quaternion = Q,
        Vector3Box = function(value) return { unbox = function() return value end } end,
        math = setmetatable({ clamp = function(value, low, high) return math.max(low, math.min(high, value)) end }, { __index = math }),
        PlayerUnitMovementSettings = { move_speed = 5,
            get_movement_settings_table = function(unit) H.equal(unit, f.unit); return n.settings end },
    }, { __index = _G })
    env._G = env
    local path = native_root .. RELATIVE
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a"); file:close()
    if source:sub(1, 3) == string.char(239, 187, 191) then source = source:sub(4) end
    local chunk = assert(loadstring(source, "@" .. path))
    setfenv(chunk, env); chunk()
    n.helper, n.vec = env.CharacterStateHelper, vec
    H.equal(type(n.helper.get_movement_input), "function", "complete native helper input must load")
    H.equal(type(n.helper.move_on_ground), "function", "complete native ground helper must load")
    H.equal(type(n.helper.move_in_air), "function", "complete native air helper must load")
    function n.reset()
        n.calls, n.rotations, n.wanted = 0, 0, nil
    end
    function n.expect(x, y, z, reason)
        H.equal(n.calls, 1, "native velocity writer must run exactly once")
        H.equal(n.rotations, 1, "native helper must run exactly once")
        H.truthy(n.wanted and math.abs(n.wanted.x - x) < 1e-12
            and math.abs(n.wanted.y - y) < 1e-12 and math.abs(n.wanted.z - z) < 1e-12, reason)
    end
    return n
end
return M
