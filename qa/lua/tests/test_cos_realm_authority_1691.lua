return function(H, repo_root)
    local base = repo_root .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
    local Factory = assert(loadfile(base .. "_cos_realm_authority.lua"))()
    local Legacy = assert(loadfile(base .. "_lib_modded_realm_authority.lua"))()

    local function load_in(path, env)
        local chunk = assert(loadfile(path))
        if setfenv then setfenv(chunk, env)
        else chunk = assert(loadfile(path, "t", env)) end
        return chunk()
    end

    H.test("Cosmetics #1691 native realm precedes every legacy authority without writes", function()
        local flags = { true, false, "true", 1 }
        for _, native in ipairs(flags) do
            local globals = { MODDED_REALM = native,
                script_data = { ["eac-untrusted"] = true },
                GameSettingsDevelopment = { read_only_backend = true } }
            local adapter = Factory.new(globals, {
                is_modded = function() error("native realm must not call legacy authority") end,
            })
            H.equal(adapter.is_modded(), native == true)
            H.equal(globals.MODDED_REALM, native)
            H.equal(globals.script_data["eac-untrusted"], true)
            H.equal(globals.GameSettingsDevelopment.read_only_backend, true)
        end
    end)

    H.test("Cosmetics #1691 absent modern flag retains only the shared pre-6.12 fallback", function()
        H.equal(Factory.new({ script_data = { ["eac-untrusted"] = true } }, Legacy).is_modded(), true)
        H.equal(Factory.new({ Development = { application_parameter = { eac_untrusted = false } } }, Legacy).is_modded(), true)
        H.equal(Factory.new({ script_data = { ["eac-untrusted"] = "true" } }, Legacy).is_modded(), false)
        local inherited = setmetatable({}, { __index = { MODDED_REALM = true } })
        H.equal(Factory.new(inherited, Legacy).is_modded(), false,
            "metatable fallbacks are not native launch authority")
    end)

    H.test("Cosmetics #1691 named check exercises the installed adapter and reports old-game SKIP", function()
        local globals = { MODDED_REALM = true }
        local adapter = Factory.new(globals, Legacy)
        local check
        adapter.install_checks(function(name, fn)
            H.equal(name, "issue1691_native_realm_authority"); check = fn
        end)
        H.equal(check(), nil)
        adapter.is_modded = function() return false end
        H.truthy(check():find("disagrees", 1, true))
        globals.MODDED_REALM = nil
        H.truthy(check():find("skip:", 1, true) == 1)
    end)

    H.test("Cosmetics #1691 actual regression runner counts missing modern context as SKIP", function()
        local Command = assert(loadfile(base .. "_cos_command_owner.lua"))()
        local Lifecycle = assert(loadfile(base .. "_cos_mod_lifecycle.lua"))()
        local commands, lines = {}, {}
        local mod = {}
        function mod:command(name, _, fn) commands[name] = fn end
        function mod:echo(fmt, ...) lines[#lines + 1] = string.format(fmt, ...) end
        function mod:info() end
        function mod:warning() end
        local register = Command.install(mod, { version = "fixture",
            local_player_safe = Lifecycle.local_player_safe })
        Factory.new({}, Legacy).install_checks(register)
        commands.cos_regression_test()
        local output = table.concat(lines, "\n")
        H.truthy(output:find("SKIP: issue1691_native_realm_authority", 1, true))
        H.truthy(output:find("1 passed, 0 failed", 1, true))
        H.truthy(output:find("1 skipped", 1, true))
        H.equal(output:find("PASS: issue1691_native_realm_authority", 1, true), nil)
    end)

    local function unlock_fixture(native, legacy_flag, frames_on)
        local env = setmetatable({}, { __index = _G })
        env._G = env
        env.MODDED_REALM = native
        env.script_data = { ["eac-untrusted"] = legacy_flag }
        env.GameSettingsDevelopment = { read_only_backend = true }
        env.ItemMasterList = setmetatable({
            free_frame = { item_type = "frame" },
            dlc_frame = { item_type = "frame" },
            es_hat_0001 = { item_type = "hat" },
        }, { __index = function() error("unknown ItemMasterList lookup") end })
        local hooks, safe_hooks = {}, {}
        local mod = { _cos = { U = { managed = {} },
            skin_requires_unowned_dlc = function(key) return key == "dlc_frame" end } }
        mod._cos_realm_authority = Factory.new(env, Legacy)
        function mod:get(name) return name == "unlock_all_frames" and frames_on == true end
        function mod:dofile(path) return load_in(repo_root .. "/cosmetics_tweaker/" .. path .. ".lua", env) end
        function mod:hook(class, method, fn)
            H.equal(class, "PlayFabMirrorAdventure"); H.equal(hooks[method], nil); hooks[method] = fn
        end
        function mod:hook_safe(class, method, fn)
            H.equal(class, "PlayFabMirrorAdventure"); H.equal(safe_hooks[method], nil); safe_hooks[method] = fn
        end
        function mod:command() end
        function mod:info() end
        env.get_mod = function() return mod end
        load_in(base .. "_cos_unlocks.lua", env)
        return hooks, safe_hooks, env
    end

    H.test("Cosmetics #1691 installed mirror injection unlocks modern modded rows and respects DLC", function()
        local hooks, _, env = unlock_fixture(true, nil, true)
        local rows, native_calls = {}, 0
        hooks._create_fake_inventory_items(function(_, target, kind)
            H.equal(target, rows); H.equal(kind, "cosmetics"); native_calls = native_calls + 1
        end, {}, rows, "cosmetics")
        H.equal(rows.free_frame, true)
        H.equal(rows.dlc_frame, nil)
        H.equal(rows.es_hat_0001, true)
        H.equal(native_calls, 1)
        H.equal(env.MODDED_REALM, true)
        H.equal(env.GameSettingsDevelopment.read_only_backend, true)
    end)

    H.test("Cosmetics #1691 installed mirror injection stays vanilla in explicit official realm", function()
        local hooks, safe = unlock_fixture(false, true, true)
        local rows, calls = {}, 0
        hooks._create_fake_inventory_items(function() calls = calls + 1 end, {}, rows, "cosmetics")
        H.equal(next(rows), nil); H.equal(calls, 1)
        local mirror = { _unlocked_cosmetics = {} }
        safe.get_unlocked_cosmetics(mirror)
        H.equal(next(mirror._unlocked_cosmetics), nil)
    end)

    H.test("Cosmetics #1691 installed resync preserves owned backend IDs and separate frame setting", function()
        local _, safe = unlock_fixture(true, nil, false)
        local rows = { es_hat_0001 = "owned_backend_id" }
        safe.get_unlocked_cosmetics({ _unlocked_cosmetics = rows })
        H.equal(rows.es_hat_0001, "owned_backend_id")
        H.equal(rows.free_frame, nil)
        local hooks = unlock_fixture(nil, true, true)
        local old_rows = {}
        hooks._create_fake_inventory_items(function() end, {}, old_rows, "cosmetics")
        H.equal(old_rows.free_frame, true, "pre-6.12 modded inventory remains supported")
    end)
end
