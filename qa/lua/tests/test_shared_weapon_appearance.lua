return function(H, repo_root)
    local source_path = repo_root .. "/tools/shared_lib/_lib_weapon_appearance.lua"
    local Library = dofile(source_path)

    local function fixture()
        local calls = {}
        local alive = setmetatable({}, { __mode = "k" })
        local api = {
            vector_new = function(x, y, z) return { x, y, z } end,
            vector_to_elements = function(v) return v[1], v[2], v[3] end,
            quaternion = {
                from_euler_angles_xyz = function(x, y, z)
                    return { kind = "quaternion", x, y, z }
                end,
            },
            unit = {},
        }
        function api.unit.alive(unit) return alive[unit] == true end
        function api.unit.local_position(unit) return unit.position end
        function api.unit.set_local_position(unit, node, value)
            unit.position = value
            calls[#calls + 1] = { "position", node, value }
        end
        function api.unit.set_local_scale(unit, node, value)
            calls[#calls + 1] = { "scale", node, value }
        end
        function api.unit.set_local_rotation(unit, node, value)
            calls[#calls + 1] = { "rotation", node, value }
        end
        function api.unit.set_texture_for_materials(unit, slot, texture)
            calls[#calls + 1] = { "texture", slot, texture }
        end
        local unit = { position = { 1, 2, 3 } }
        alive[unit] = true
        return Library.new(api), unit, calls, alive
    end

    H.test("shared WeaponAppearance composes absolute transforms and one additive offset", function()
        local WA, unit, calls = fixture()
        H.truthy(WA.apply(unit, {
            scale = { 2, 3, 4 },
            offset = { 0.5, -1, 2 },
            rotation = { 10, 20, 30 },
        }))
        H.equal(#calls, 3)
        H.equal(calls[1][1], "scale")
        H.equal(calls[2][1], "position")
        H.equal(unit.position[1], 1.5)
        H.equal(unit.position[2], 1)
        H.equal(unit.position[3], 5)
        H.equal(calls[3][1], "rotation")
        H.equal(calls[3][3].kind, "quaternion")
        H.equal(WA.apply_offset(unit, { 9, 9, 9 }), false)
        H.equal(#calls, 3)
    end)

    H.test("shared WeaponAppearance gives absolute position precedence over offset", function()
        local WA, unit, calls = fixture()
        H.truthy(WA.apply(unit, { position = { 4, 5, 6 }, offset = { 9, 9, 9 } }))
        H.equal(#calls, 1)
        H.equal(unit.position[1], 4)
        H.equal(unit.position[2], 5)
        H.equal(unit.position[3], 6)
    end)

    H.test("shared WeaponAppearance normalizes Euler and boxed rotations", function()
        local WA = fixture()
        local euler = WA.to_quaternion({ 90, 0, -45 })
        H.equal(euler.kind, "quaternion")
        H.equal(euler[1], 90)
        H.equal(euler[3], -45)
        local boxed = { unbox = function() return "raw-q" end }
        H.equal(WA.to_quaternion(boxed), "raw-q")
        H.equal(WA.to_quaternion({ "bad", 0, 0 }), nil)
    end)

    H.test("shared WeaponAppearance texture writes are per-unit and bounded", function()
        local WA, unit, calls = fixture()
        local ok, count = WA.apply_textures(unit, {
            { slot = "albedo", texture = "textures/a" },
            { slot = "normal", texture = "textures/n" },
        })
        H.equal(ok, true)
        H.equal(count, 2)
        H.equal(calls[1][1], "texture")
        H.equal(calls[2][1], "texture")
        local file = assert(io.open(source_path, "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find("unit_api.set_texture_for_materials", 1, true))
        H.equal(source:find("Material" .. ".set_texture(", 1, true), nil)
    end)

    H.test("shared WeaponAppearance fails closed on dead units and malformed specs", function()
        local WA, unit, calls, alive = fixture()
        alive[unit] = false
        H.equal(WA.apply(unit, { scale = { 1, 1, 1 } }), false)
        H.equal(WA.apply_scale(unit, { 1, 1 }), false)
        H.equal(WA.apply_textures(unit, { albedo = "textures/a" }), false)
        H.equal(#calls, 0)
    end)

    H.test("shared WeaponAppearance consumer copies are byte-identical", function()
        local function read(path)
            local file = assert(io.open(path, "rb"))
            local value = file:read("*a")
            file:close()
            return value
        end
        local canonical = read(source_path)
        for _, path in ipairs({
            "/character_weapon_variants/scripts/mods/character_weapon_variants/_lib_weapon_appearance.lua",
            "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_lib_weapon_appearance.lua",
            "/weapon_tweaker/scripts/mods/weapon_tweaker/_lib_weapon_appearance.lua",
        }) do
            H.equal(read(repo_root .. path), canonical, path .. " drifted")
        end
    end)

    H.test("CWV #420 loads its local copy and preserves compatibility handles", function()
        local path = repo_root
            .. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua"
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find('"scripts/mods/character_weapon_variants/_lib_weapon_appearance"', 1, true))
        H.truthy(source:find("local WA = _WA_LIBRARY.new()", 1, true))
        H.truthy(source:find("mod._wa_to_quaternion_for_rt = WA.to_quaternion", 1, true))
        H.truthy(source:find("mod._cwv_weapon_appearance = WA", 1, true))
        H.equal(source:find("function WA.apply_scale", 1, true), nil)
        H.equal(source:find("local _offset_applied", 1, true), nil)
    end)
end
