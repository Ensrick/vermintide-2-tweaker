return function(H, repo_root)
    local stable_path = repo_root .. "/gui_tweaker/scripts/mods/gui_tweaker/_gut_inventory_backdrop.lua"
    local dev_path = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_inventory_backdrop.lua"

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function with_runtime(path, expected_mod_id, body)
        local saved = {
            get_mod = _G.get_mod,
            World = _G.World,
            ShadingEnvironment = _G.ShadingEnvironment,
            printf = _G.printf,
            HeroWindowCharacterPreview = _G.HeroWindowCharacterPreview,
        }
        local mod = { hooks = {}, setting = "dim" }
        function mod:get(setting_id)
            H.equal(setting_id, "gut_inventory_backdrop")
            return self.setting
        end
        function mod:hook(class_name, method_name, wrapper)
            H.equal(class_name, "HeroWindowCharacterPreview")
            self.hooks[method_name] = wrapper
        end

        _G.get_mod = function(mod_id)
            H.equal(mod_id, expected_mod_id)
            return mod
        end
        _G.printf = function() end
        _G.World = {
            has_data = function(world, key) return world.data[key] ~= nil end,
            get_data = function(world, key) return world.data[key] end,
            set_data = function(world, key, value) world.data[key] = value end,
        }
        _G.ShadingEnvironment = {
            scalar = function(env, key)
                H.equal(key, "exposure")
                return env.exposure
            end,
            set_scalar = function(env, key, value)
                H.equal(key, "exposure")
                env.exposure = value
            end,
        }
        _G.HeroWindowCharacterPreview = {
            post_update = function() end,
            on_exit = function() end,
        }

        local ok, failure = xpcall(function()
            local module = assert(loadfile(path))()
            body(mod, module)
        end, debug.traceback)

        _G.get_mod = saved.get_mod
        _G.World = saved.World
        _G.ShadingEnvironment = saved.ShadingEnvironment
        _G.printf = saved.printf
        _G.HeroWindowCharacterPreview = saved.HeroWindowCharacterPreview
        if not ok then
            error(failure, 0)
        end
    end

    H.test("GUT #522 scopes exposure to only the inventory preview world", function()
        with_runtime(stable_path, "gut", function(mod)
            local prior_calls = 0
            local prior = function() prior_calls = prior_calls + 1 end
            local preview_world = { data = { shading_callback = prior } }
            local mission_callback = function() end
            local mission_world = { data = { shading_callback = mission_callback } }
            local window = {}
            local vanilla_post_calls = 0

            mod.hooks.post_update(function(self)
                vanilla_post_calls = vanilla_post_calls + 1
                self.world_previewer = { world = preview_world }
            end, window, 0, 0)

            H.equal(vanilla_post_calls, 1)
            local installed = preview_world.data.shading_callback
            H.truthy(type(installed) == "function" and installed ~= prior)
            H.equal(mission_world.data.shading_callback, mission_callback,
                "non-preview world callback was changed")

            local env = { exposure = 10 }
            installed(preview_world, env, {})
            H.equal(prior_calls, 1, "prior callback was not chained")
            H.equal(env.exposure, 6.5)
            H.equal(mission_world.data.shading_callback, mission_callback,
                "hot path touched the mission world")
        end)
    end)

    H.test("GUT #522 updates in place and restores the exact prior callback", function()
        with_runtime(stable_path, "gut", function(mod)
            local prior = function() end
            local world = { data = { shading_callback = prior } }
            local window = { world_previewer = { world = world } }
            mod.hooks.post_update(function() end, window, 0, 0)
            local installed = world.data.shading_callback

            mod.setting = "dark"
            mod.on_setting_changed("gut_inventory_backdrop")
            H.equal(world.data.shading_callback, installed,
                "setting change allocated/reinstalled the callback")
            local env = { exposure = 10 }
            installed(world, env, {})
            H.equal(env.exposure, 4)

            mod.setting = "vanilla"
            mod.on_setting_changed("gut_inventory_backdrop")
            H.equal(world.data.shading_callback, prior,
                "Vanilla did not restore the exact prior callback")

            mod.setting = "dim"
            mod.hooks.post_update(function() end, window, 0, 0)
            H.truthy(world.data.shading_callback ~= prior)
            mod.hooks.on_exit(function()
                H.equal(world.data.shading_callback, prior,
                    "on_exit delegated before restoring the callback")
            end, window)
            H.equal(world.data.shading_callback, prior)
        end)
    end)

    H.test("GUT #522 migrates legacy choices and keeps stable/dev policy mirrored", function()
        with_runtime(dev_path, "gut_dev", function(mod)
            H.equal(mod._gut_inv_lighting_normalize("dark_camp"), "dim")
            H.equal(mod._gut_inv_lighting_normalize("victory_camp"), "dark")
            H.equal(mod._gut_inv_lighting_normalize("unknown"), "vanilla")
            H.equal(mod._gut_inv_lighting_profiles.vanilla, 1)
            H.equal(mod._gut_inv_lighting_profiles.dim, 0.65)
            H.equal(mod._gut_inv_lighting_profiles.dark, 0.4)
        end)

        local function canonical(source)
            return source:gsub("\r\n", "\n"):match("^%s*(.-)%s*$")
        end
        local stable = canonical(read(stable_path))
        local dev = canonical(read(dev_path))
            :gsub('get_mod%("gut_dev"%)', 'get_mod("gut")')
            :gsub("%[gut_dev:522%]", "[gut:522]")
        H.equal(dev, stable, "stable/dev inventory-lighting implementations drifted")
        H.equal(stable:find("Managers.package", 1, true), nil)
        H.equal(stable:find("vp.level_name", 1, true), nil)
        H.equal(stable:find('mod:hook("HeroWindowCharacterPreview", "create_ui_elements"', 1, true), nil)
        H.truthy(stable:find("window.world_previewer", 1, true))
        H.truthy(stable:find('WorldApi.set_data(world, "shading_callback", state.had_prior and state.prior or nil)', 1, true))
    end)
end
