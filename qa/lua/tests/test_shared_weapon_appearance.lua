return function(H, repo_root)
    local source_path = repo_root .. "/tools/shared_lib/_lib_weapon_appearance.lua"
    local Library = dofile(source_path)

    local function fixture(options)
        options = options or {}
        local calls = {}
        local alive = setmetatable({}, { __mode = "k" })
        local api = {
            vector_new = options.vector_new
                or function(x, y, z) return { x, y, z } end,
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
        function api.unit.local_scale(unit) return unit.scale end
        function api.unit.local_rotation(unit) return unit.rotation end
        function api.unit.set_local_position(unit, node, value)
            if options.fail_position then error("position rejected") end
            if not options.channel_noop then unit.position = value end
            calls[#calls + 1] = { "position", node, value }
        end
        function api.unit.set_local_scale(unit, node, value)
            if options.fail_scale then error("scale rejected") end
            if not options.channel_noop then unit.scale = value end
            calls[#calls + 1] = { "scale", node, value }
        end
        function api.unit.set_local_rotation(unit, node, value)
            if options.fail_rotation then error("rotation rejected") end
            if not options.channel_noop then unit.rotation = value end
            calls[#calls + 1] = { "rotation", node, value }
        end
        function api.unit.set_texture_for_materials(unit, slot, texture)
            calls[#calls + 1] = { "texture", slot, texture }
        end
        if options.atomic ~= false then
            api.matrix4x4 = {
                from_quaternion_position_scale = function(rotation, position, scale)
                    return { rotation = rotation, position = position, scale = scale }
                end,
            }
            function api.unit.set_local_pose(unit, node, pose)
                if options.reject_node_zero and node == 0 then
                    error("linked root rejected pose")
                end
                unit.position = pose.position
                unit.scale = pose.scale
                unit.rotation = pose.rotation
                calls[#calls + 1] = { "pose", node, pose }
            end
        end
        local unit = {
            position = { 1, 2, 3 }, scale = { 1, 1, 1 },
            rotation = { kind = "quaternion", 0, 0, 0 },
        }
        alive[unit] = true
        return Library.new(api), unit, calls, alive
    end

    local function with_engine_globals(values, callback)
        local old = {}
        for name, value in pairs(values) do
            old[name] = rawget(_G, name)
            rawset(_G, name, value)
        end
        local ok, message = pcall(callback)
        for name in pairs(values) do rawset(_G, name, old[name]) end
        if not ok then error(message, 0) end
    end

    H.test("shared WeaponAppearance composes absolute transforms and one additive offset", function()
        local WA, unit, calls = fixture()
        local ok, report = WA.apply(unit, {
            scale = { 2, 3, 4 },
            offset = { 0.5, -1, 2 },
            rotation = { 10, 20, 30 },
        })
        H.equal(ok, true)
        H.equal(report.transform_mode, "atomic-local-pose")
        H.equal(#calls, 1)
        H.equal(calls[1][1], "pose")
        H.equal(unit.position[1], 1.5)
        H.equal(unit.position[2], 1)
        H.equal(unit.position[3], 5)
        H.equal(unit.scale[2], 3)
        H.equal(unit.rotation.kind, "quaternion")
        H.equal(WA.apply_offset(unit, { 9, 9, 9 }), false)
        H.equal(#calls, 1)
    end)

    H.test("shared WeaponAppearance default API accepts retail callable-table Vector3", function()
        local vector3 = setmetatable({
            to_elements = function(value) return value[1], value[2], value[3] end,
        }, {
            __call = function(_, x, y, z) return { x, y, z } end,
        })
        local calls = {}
        local alive = setmetatable({}, { __mode = "k" })
        local unit_api = {}
        function unit_api.alive(unit) return alive[unit] == true end
        function unit_api.local_position(unit) return unit.position end
        function unit_api.local_scale(unit) return unit.scale end
        function unit_api.local_rotation(unit) return unit.rotation end
        function unit_api.set_local_position(unit, node, value)
            unit.position = value
            calls[#calls + 1] = { "position", node, value }
        end
        function unit_api.set_local_scale(unit, node, value)
            unit.scale = value
            calls[#calls + 1] = { "scale", node, value }
        end
        function unit_api.set_local_pose(unit, node, pose)
            unit.position, unit.scale, unit.rotation =
                pose.position, pose.scale, pose.rotation
            calls[#calls + 1] = { "pose", node, pose }
        end
        local quaternion = {
            from_euler_angles_xyz = function(x, y, z)
                return { kind = "quaternion", x, y, z }
            end,
        }
        local matrix4x4 = {
            from_quaternion_position_scale = function(rotation, position, scale)
                return { rotation = rotation, position = position, scale = scale }
            end,
        }
        local unit = {
            position = { 1, 2, 3 }, scale = { 1, 1, 1 },
            rotation = { kind = "quaternion", 0, 0, 0 },
        }
        local offset_unit = {
            position = { 10, 20, 30 }, scale = { 1, 1, 1 },
            rotation = { kind = "quaternion", 0, 0, 0 },
        }
        local atomic_offset_unit = {
            position = { 2, 4, 6 }, scale = { 1, 1, 1 },
            rotation = { kind = "quaternion", 0, 0, 0 },
        }
        alive[unit], alive[offset_unit], alive[atomic_offset_unit] =
            true, true, true

        with_engine_globals({
            Vector3 = vector3,
            Unit = unit_api,
            Quaternion = quaternion,
            Matrix4x4 = matrix4x4,
        }, function()
            local WA = Library.new()
            local ok, report = WA.apply(unit, {
                position = { 4, 5, 6 }, scale = { 0.9, 0.8, 0.7 },
                rotation = { -90, -90, -90 },
            })
            H.equal(ok, true)
            H.equal(report.transform_mode, "atomic-local-pose")
            H.deep_equal(unit.position, { 4, 5, 6 })
            H.deep_equal(unit.scale, { 0.9, 0.8, 0.7 })
            H.equal(WA.apply_position(unit, { 7, 8, 9 }, 1), true)
            H.equal(WA.apply_scale(unit, { 2, 3, 4 }, 1), true)
            H.equal(WA.apply_offset(offset_unit, { 0.5, -1, 2 }), true)
            H.deep_equal(offset_unit.position, { 10.5, 19, 32 })
            local offset_ok, offset_report = WA.apply(atomic_offset_unit, {
                offset = { -1, 0.5, 3 },
            })
            H.equal(offset_ok, true)
            H.equal(offset_report.transform_mode, "atomic-local-pose")
            H.deep_equal(atomic_offset_unit.position, { 1, 4.5, 9 })
        end)
        H.equal(#calls, 5)
    end)

    H.test("shared WeaponAppearance callable constructor failures remain bounded", function()
        local constructors = {
            {},
            setmetatable({}, { __call = function() error("constructor rejected") end }),
            setmetatable({}, { __call = function() return nil end }),
        }
        for _, constructor in ipairs(constructors) do
            local WA, unit, calls = fixture({ vector_new = constructor })
            local ok, report = WA.apply(unit, {
                position = { 4, 5, 6 }, scale = { 2, 2, 2 },
            })
            H.equal(ok, false)
            H.equal(report.transform_mode, "atomic-local-pose")
            H.equal(report.transform_error, "invalid-position")
            H.equal(WA.apply_position(unit, { 4, 5, 6 }), false)
            H.equal(WA.apply_scale(unit, { 2, 2, 2 }), false)
            H.equal(WA.apply_offset(unit, { 1, 1, 1 }), false)
            H.equal(#calls, 0)
        end
    end)

    H.test("shared WeaponAppearance has no function-only Vector3 guard", function()
        local file = assert(io.open(source_path, "rb"))
        local source = file:read("*a")
        file:close()
        H.equal(source:find('type(vector_new) ~= "function"', 1, true), nil)
        H.equal(source:find('type(vector_new) == "function"', 1, true), nil)
    end)

    H.test("shared WeaponAppearance gives absolute position precedence over offset", function()
        local WA, unit, calls = fixture()
        H.truthy(WA.apply(unit, { position = { 4, 5, 6 }, offset = { 9, 9, 9 } }))
        H.equal(#calls, 1)
        H.equal(calls[1][1], "pose")
        H.equal(unit.position[1], 4)
        H.equal(unit.position[2], 5)
        H.equal(unit.position[3], 6)
    end)

    H.test("shared WeaponAppearance cannot mask a failed transform channel", function()
        local WA, unit, calls = fixture({ atomic = false, fail_scale = true })
        local ok, report = WA.apply(unit, {
            scale = { 2, 2, 2 }, position = { 4, 5, 6 }, rotation = { 1, 2, 3 },
        })
        H.equal(ok, false)
        H.equal(report.transform_mode, "per-channel-fallback")
        H.equal(report.channels.scale, false)
        H.equal(report.channels.position, true)
        H.equal(report.channels.rotation, true)
        H.equal(#calls, 2)
    end)

    H.test("shared WeaponAppearance uses one pose write for a linked root", function()
        local WA, unit, calls = fixture({ channel_noop = true })
        local ok, report = WA.apply(unit, {
            scale = { 0.9, 0.9, 0.9 },
            position = { 0, 0, -0.3 },
            rotation = { -90, -90, -90 },
        })
        H.equal(ok, true)
        H.equal(report.transform_mode, "atomic-local-pose")
        H.equal(#calls, 1)
        H.deep_equal(unit.position, { 0, 0, -0.3 })
        H.deep_equal(unit.scale, { 0.9, 0.9, 0.9 })
    end)

    H.test("shared WeaponAppearance targets a proven render node when the linked root rejects pose", function()
        local WA, unit, calls = fixture({ reject_node_zero = true })
        local root_ok, root_report = WA.apply(unit, {
            scale = { 0.9, 0.9, 0.9 }, position = { 0, 0, -0.3 },
            rotation = { -90, -90, -90 },
        })
        H.equal(root_ok, false)
        H.equal(root_report.transform_node, 0)
        H.truthy(type(root_report.transform_error) == "string")
        H.truthy(#root_report.transform_error <= 160)
        local mesh_ok, mesh_report = WA.apply(unit, {
            node = 2, scale = { 0.9, 0.9, 0.9 }, position = { 0, 0, -0.3 },
            rotation = { -90, -90, -90 },
        })
        H.equal(mesh_ok, true)
        H.equal(mesh_report.transform_node, 2)
        H.equal(mesh_report.transform_error, nil)
        H.equal(calls[#calls][1], "pose")
        H.equal(calls[#calls][2], 2)
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

    local function read_repo(path)
        local file = assert(io.open(repo_root .. path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function count_plain(source, needle)
        local count, cursor = 0, 1
        while true do
            local index = source:find(needle, cursor, true)
            if not index then return count end
            count = count + 1
            cursor = index + #needle
        end
    end

    local function cosmetics_adoption_errors(entry, render)
        local errors = {}
        local function require_plain(source, needle, message)
            if not source:find(needle, 1, true) then errors[#errors + 1] = message end
        end
        require_plain(entry,
            '"scripts/mods/cosmetics_tweaker/_lib_weapon_appearance"',
            "entry does not load the Cosmetics-local shared library")
        require_plain(entry, "mod._cos.weapon_appearance = WEAPON_APPEARANCE",
            "entry does not publish its one shared instance")
        require_plain(render,
            "local _WEAPON_APPEARANCE = mod._cos.weapon_appearance",
            "ordinary render adapter does not capture the shared instance")
        if count_plain(render, "_WEAPON_APPEARANCE.apply(") < 2 then
            errors[#errors + 1] = "scale and offset channels are not both delegated"
        end
        for _, setter in ipairs({ "Unit.set_local_scale", "Unit.set_local_position" }) do
            if render:find(setter, 1, true) then
                errors[#errors + 1] = "ordinary render adapter restored private " .. setter
            end
        end
        local publish = entry:find(
            "mod._cos.weapon_appearance = WEAPON_APPEARANCE", 1, true)
        local load_render = entry:find(
            'mod:dofile("scripts/mods/cosmetics_tweaker/_cos_render")', 1, true)
        if not publish or not load_render or publish >= load_render then
            errors[#errors + 1] = "shared instance is not installed before _cos_render"
        end
        return errors
    end

    H.test("#420 Cosmetics ordinary transform adapter delegates to shared WeaponAppearance", function()
        local entry = read_repo(
            "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua")
        local render = read_repo(
            "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_render.lua")
        local errors = cosmetics_adoption_errors(entry, render)
        H.equal(#errors, 0, table.concat(errors, "; "))
        H.truthy(render:find("local descriptor = { scale = scale }", 1, true))
        H.truthy(render:find(
            "local descriptor = { offset = { offset[1], offset[2], offset[3] } }",
            1, true))
    end)

    H.test("#420 Cosmetics adoption rejects private scale and position setters", function()
        local entry = read_repo(
            "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua")
        local render = read_repo(
            "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_render.lua")
        for _, setter in ipairs({ "Unit.set_local_scale", "Unit.set_local_position" }) do
            local adversarial = render .. "\n" .. setter .. "(unit, 0, value)\n"
            local errors = cosmetics_adoption_errors(entry, adversarial)
            H.truthy(#errors > 0, setter .. " regression was not rejected")
            H.truthy(table.concat(errors, "; "):find(setter, 1, true),
                setter .. " rejection did not identify the private owner")
        end
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
            "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_lib_weapon_appearance.lua",
            "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_lib_weapon_appearance.lua",
        }) do
            H.equal(read(repo_root .. path), canonical, path .. " drifted")
        end
    end)

    H.test("CWV #420 loads its local copy and preserves compatibility handles", function()
        -- #1159: the WA load and both compatibility handles moved verbatim out of
        -- the entry into the weapon-transform owner. The gate follows the code.
        local path = repo_root
            .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_weapon_transform_owner.lua"
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

    H.test("#420 ordinary WT adapters consume shared WeaponAppearance", function()
        local function read(path)
            local file = assert(io.open(repo_root .. path, "rb"))
            local source = file:read("*a")
            file:close()
            return source
        end
        local consumers = {
            {
                path = "/weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker.lua",
                runtime = "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_transform_runtime.lua",
                loader = '"scripts/mods/weapon_tweaker/_lib_weapon_appearance"',
                export = "mod._wt_weapon_appearance = _WEAPON_APPEARANCE",
            },
            {
                path = "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/weapon_tweaker_dev.lua",
                runtime = "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_transform_runtime.lua",
                loader = '"scripts/mods/weapon_tweaker_dev/_lib_weapon_appearance"',
                export = "mod._wt_weapon_appearance = _WEAPON_APPEARANCE",
            },
        }
        for _, consumer in ipairs(consumers) do
            local source = read(consumer.path)
            H.truthy(source:find(consumer.loader, 1, true), consumer.path)
            H.truthy(source:find(consumer.export, 1, true), consumer.path)
            H.truthy(read(consumer.runtime):find("appearance.apply(unit", 1, true), consumer.runtime)
        end

        for _, consumer in ipairs(consumers) do
            local source = read(consumer.path) .. read(consumer.runtime)
            H.equal(source:find(
                "pcall(Unit.set_local_scale, unit, 0, scale)", 1, true), nil)
            H.equal(source:find(
                "pcall(Unit.set_local_position, unit, 0, current + pos)", 1, true), nil)
            -- Durable animation-tick retention and #569 rotation composition
            -- deliberately remain specialized absolute owners.
            H.truthy(source:find(
                "function mod._reapply_durable_grip_offsets()", 1, true))
            H.truthy(source:find(
                "function mod._wt569_reapply_3p_orientation()", 1, true))
        end
    end)
end
