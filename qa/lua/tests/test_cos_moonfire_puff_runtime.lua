return function(H, repo_root)
    local root = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
    local owner_path = root .. "_cos_moonfire_puff_runtime.lua"
    local entry_path = root .. "cosmetics_tweaker.lua"
    local Runtime = dofile(owner_path)

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function count(source, needle)
        local n, at = 0, 1
        while true do
            local found = source:find(needle, at, true)
            if not found then return n end
            n = n + 1
            at = found + #needle
        end
    end

    local function fixture()
        local hooks = {}
        local particles = {}
        local enabled = true
        local wt_enabled = false
        local classes = {}
        for _, name in ipairs({
            "PlayerProjectileUnitExtension",
            "PlayerProjectileHuskExtension",
        }) do
            classes[name] = {
                hit_enemy = function() end,
                hit_level_unit = function() end,
                hit_non_level_unit = function() end,
            }
        end
        local mod = {}
        function mod:get(key)
            if key == "cos_moonfire_cosmetic_puff" then return enabled end
        end
        function mod:hook_safe(target, method, callback)
            hooks[#hooks + 1] = {
                target = target, method = method, callback = callback,
            }
        end
        local deps = {
            get_mod = function(name)
                if name == "wt" then
                    return { get = function(_, key)
                        return key == "moonfire_aoe_revert" and wt_enabled
                    end }
                end
            end,
            get_class = function(name) return classes[name] end,
            get_world = function() return {
                create_particles = function(world, fx, position, rotation)
                    particles[#particles + 1] = {
                        world = world, fx = fx, position = position,
                        rotation = rotation,
                    }
                end,
            } end,
            get_quaternion = function()
                return { identity = function() return "identity" end }
            end,
        }
        local owner = Runtime.install(mod, deps)
        return {
            mod = mod, deps = deps, owner = owner,
            hooks = hooks, particles = particles,
            set_enabled = function(value) enabled = value end,
            set_wt_enabled = function(value) wt_enabled = value end,
        }
    end

    H.test("Cosmetics Moonfire puff runtime exclusively owns six bounded hooks", function()
        local entry = read(entry_path)
        local source = read(owner_path)
        H.equal(count(entry,
            'mod:dofile("scripts/mods/cosmetics_tweaker/_cos_moonfire_puff_runtime").install'), 1)
        H.equal(count(entry, "PlayerProjectileUnitExtension"), 0)
        H.equal(count(entry, "PlayerProjectileHuskExtension"), 0)
        H.equal(count(source, '"PlayerProjectileUnitExtension"'), 1)
        H.equal(count(source, '"PlayerProjectileHuskExtension"'), 1)
        for _, forbidden in ipairs({
            "network_register", "network_send", "mod:command(", "mod.update",
            "on_game_state_changed", "on_disabled", "on_unload", "mod:dofile(",
        }) do
            H.equal(source:find(forbidden, 1, true), nil, forbidden)
        end
    end)

    H.test("Cosmetics Moonfire puff preserves gates and does not double WT AOE", function()
        local f = fixture()
        H.equal(#f.hooks, 6)
        H.equal(f.owner.hook_count, 6)
        local callback = f.hooks[1].callback
        local projectile = { item_name = "we_deus_01_skin_02", _world = "world" }
        callback(projectile, nil, nil, "impact")
        H.equal(#f.particles, 1)
        H.equal(f.particles[1].fx, "fx/wpnfx_we_deus_01_impact")
        H.equal(f.particles[1].rotation, "identity")

        callback({ item_name = "longbow", _world = "world" }, nil, nil, "impact")
        f.set_enabled(false)
        callback(projectile, nil, nil, "impact")
        f.set_enabled(true)
        f.set_wt_enabled(true)
        callback(projectile, nil, nil, "impact")
        callback({ item_name = "we_deus_01", _world = nil }, nil, nil, "impact")
        H.equal(#f.particles, 1)
    end)

    H.test("Cosmetics Moonfire puff install is idempotent and refreshes dependencies", function()
        local f = fixture()
        local replacement = {}
        for key, value in pairs(f.deps) do replacement[key] = value end
        local replacement_particles = 0
        replacement.get_world = function() return {
            create_particles = function()
                replacement_particles = replacement_particles + 1
            end,
        } end
        local again = Runtime.install(f.mod, replacement)
        H.equal(again, f.owner)
        H.equal(#f.hooks, 6)
        f.hooks[1].callback({
            item_name = "we_deus_01", _world = "world",
        }, nil, nil, "impact")
        H.equal(replacement_particles, 1)
    end)

    H.test("Cosmetics Moonfire puff resolves optional engine tables at impact time", function()
        local callback
        local world_api
        local quaternion
        local particles = 0
        local class = { hit_enemy = function() end }
        local mod = {}
        function mod:get() return true end
        function mod:hook_safe(_, _, hook) callback = hook end
        local owner = Runtime.install(mod, {
            get_mod = function() return nil end,
            get_class = function(name)
                if name == "PlayerProjectileUnitExtension" then return class end
            end,
            get_world = function() return world_api end,
            get_quaternion = function() return quaternion end,
        })
        H.equal(owner.hook_count, 1)
        world_api = {
            create_particles = function() particles = particles + 1 end,
        }
        quaternion = { identity = function() return "identity" end }
        callback({ item_name = "we_deus_01", _world = "world" }, nil, nil, "impact")
        H.equal(particles, 1)
    end)
end
