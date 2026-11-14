-- Functional (not inert) Vector3/Quaternion value types for load-time math in vanilla
-- data files. Engine values are userdata temporaries; here they are tables with
-- operator metatables. Boxes are metatable-free tables so table.clone accepts them.
local V = {}
local vmt = {}
local function vec3(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0, [1] = x or 0, [2] = y or 0, [3] = z or 0 }, vmt) end
local function isvec(v) return getmetatable(v) == vmt end
vmt.__add = function(a, b) return vec3(a.x + b.x, a.y + b.y, a.z + b.z) end
vmt.__sub = function(a, b) return vec3(a.x - b.x, a.y - b.y, a.z - b.z) end
vmt.__unm = function(a) return vec3(-a.x, -a.y, -a.z) end
vmt.__mul = function(a, b)
    if type(a) == "number" then return vec3(a * b.x, a * b.y, a * b.z) end
    if type(b) == "number" then return vec3(a.x * b, a.y * b, a.z * b) end
    return vec3(a.x * b.x, a.y * b.y, a.z * b.z)
end
vmt.__div = function(a, b) return vec3(a.x / b, a.y / b, a.z / b) end
vmt.__index = function(t, k) return rawget(V, k) end

local qmt = {}
local function quat(x, y, z, w) return setmetatable({ x = x or 0, y = y or 0, z = z or 0, w = w or 1 }, qmt) end
local Q = {}
qmt.__index = function(t, k) return rawget(Q, k) end

V.zero = function() return vec3(0, 0, 0) end
V.up = function() return vec3(0, 0, 1) end
V.down = function() return vec3(0, 0, -1) end
V.forward = function() return vec3(0, 1, 0) end
V.backward = function() return vec3(0, -1, 0) end
V.right = function() return vec3(1, 0, 0) end
V.left = function() return vec3(-1, 0, 0) end
V.x = function(v) return v.x end
V.y = function(v) return v.y end
V.z = function(v) return v.z end
V.to_elements = function(v) return v.x, v.y, v.z end
V.dot = function(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
V.cross = function(a, b) return vec3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x) end
V.length = function(v) return math.sqrt(V.dot(v, v)) end
V.length_squared = function(v) return V.dot(v, v) end
V.distance = function(a, b) return V.length(a - b) end
V.distance_squared = function(a, b) return V.length_squared(a - b) end
V.normalize = function(v) local l = V.length(v); if l == 0 then return vec3(0, 0, 0) end; return v / l end
V.lerp = function(a, b, t) return a + (b - a) * t end
V.set_xyz = function(v, x, y, z) v.x, v.y, v.z = x, y, z end

Q.identity = function() return quat(0, 0, 0, 1) end
Q.axis_angle = function(axis, angle)
    local s = math.sin(angle / 2)
    return quat(axis.x * s, axis.y * s, axis.z * s, math.cos(angle / 2))
end
Q.multiply = function(a, b)
    return quat(a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
        a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
        a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
        a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z)
end
Q.rotate = function(q, v)
    local qv = vec3(q.x, q.y, q.z)
    local t = V.cross(qv, v) * 2
    return v + t * q.w + V.cross(qv, t)
end
Q.to_elements = function(q) return q.x, q.y, q.z, q.w end
Q.from_elements = function(x, y, z, w) return quat(x, y, z, w) end
Q.from_euler_angles_xyz = function() return quat(0, 0, 0, 1) end
Q.look = function() return quat(0, 0, 0, 1) end
Q.forward = function(q) return Q.rotate(q, vec3(0, 1, 0)) end
Q.right = function(q) return Q.rotate(q, vec3(1, 0, 0)) end
Q.up = function(q) return Q.rotate(q, vec3(0, 0, 1)) end
Q.inverse = function(q) return quat(-q.x, -q.y, -q.z, q.w) end
qmt.__mul = Q.multiply

local function box_of(get)
    return function(a, b, c, d)
        local box = { a, b, c, d }
        if type(a) == "table" then box = { a.x, a.y, a.z, a.w } end
        box.unbox = function(self) return get(self[1], self[2], self[3], self[4]) end
        box.store = function(self, v, y, z, w)
            if type(v) == "table" then self[1], self[2], self[3], self[4] = v.x, v.y, v.z, v.w else self[1], self[2], self[3], self[4] = v, y, z, w end
        end
        return box
    end
end

return {
    Vector3 = setmetatable(V, { __call = function(_, x, y, z) return vec3(x, y, z) end }),
    Quaternion = setmetatable(Q, { __call = function(_, a, b, c, d)
        if type(a) == "table" then return Q.axis_angle(a, b or 0) end
        return quat(a, b, c, d)
    end }),
    Vector3Box = box_of(function(x, y, z) return vec3(x, y, z) end),
    QuaternionBox = box_of(function(x, y, z, w) return quat(x, y, z, w) end),
}
