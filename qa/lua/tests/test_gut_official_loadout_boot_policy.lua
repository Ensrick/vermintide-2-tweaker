return function(H, repo_root)
    local policy_path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_official_loadout_boot_policy.lua"
    local Policy = assert(loadfile(policy_path))()

    local function with_guard(metadata_realm, eac_untrusted, body)
        local saved_get_mod, saved_managers = _G.get_mod, _G.Managers
        local saved_script_data, saved_printf = _G.script_data, _G.printf
        local hooks = {}
        local fake_mod = {
            dofile = function() return Policy end,
            hook = function(_, _, method, callback) hooks[method] = callback end,
        }
        _G.get_mod = function() return fake_mod end
        _G.Managers = { backend = { _metadata = { realm = metadata_realm } } }
        _G.script_data = { ["eac-untrusted"] = eac_untrusted }
        _G.printf = function() end
        local guard_path = repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_official_loadout_boot_guard.lua"
        local ok_load, guard = pcall(assert(loadfile(guard_path)))
        local ok_body, body_error
        if ok_load then ok_body, body_error = pcall(body, guard, hooks) end
        _G.get_mod, _G.Managers = saved_get_mod, saved_managers
        _G.script_data, _G.printf = saved_script_data, saved_printf
        if not ok_load then error(guard) end
        if not ok_body then error(body_error) end
    end

    H.test("issue 402 stable backend realm outranks a transient EAC flag", function()
        H.equal(Policy.realm_is_modded("modded", false), true)
        H.equal(Policy.realm_is_modded("official", true), false)
        H.equal(Policy.realm_is_modded(nil, true), true)
        H.equal(Policy.realm_is_modded(nil, false), false)
    end)

    H.test("issue 402 boot guard is modded Adventure only", function()
        H.equal(Policy.guard_active(true, "characters_data", "characters_data"), true)
        H.equal(Policy.guard_active(false, "characters_data", "characters_data"), false)
        H.equal(Policy.guard_active(true, "vs_characters_data", "characters_data"), false)
        H.equal(Policy.guard_active(true, nil, "characters_data"), false)
    end)

    H.test("issue 402 callback bookkeeping is bounded", function()
        H.equal(Policy.decrement_pending(3), 2)
        H.equal(Policy.decrement_pending(0), 0)
        H.equal(Policy.decrement_pending(nil), 0)
        H.equal(Policy.fix_continuation(1), "inventory")
        H.equal(Policy.fix_continuation(0), "default_gear")
        H.equal(Policy.fix_continuation(nil), "default_gear")
        H.equal(Policy.allow_verify_bootstrap(false), true)
        H.equal(Policy.allow_verify_bootstrap(nil), true)
        H.equal(Policy.allow_verify_bootstrap(true), false)
    end)

    H.test("issue 402 early owner covers every destructive boot seam", function()
        local guard_path = repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_official_loadout_boot_guard.lua"
        local file = assert(io.open(guard_path, "rb"))
        local source = file:read("*a")
        file:close()
        local required = {
            "_set_inital_career_data", "_fix_career_data", "fix_career_data_request_cb",
            "_verify_career_loadouts", "verify_career_loadouts_cb",
        }
        for _, method in ipairs(required) do
            H.truthy(source:find('mod:hook("PlayFabMirrorAdventure", "' .. method .. '"', 1, true),
                "missing boot hook " .. method)
        end
        H.truthy(source:find("NO_VERIFY_SLOTS", 1, true),
            "snapshot import does not suppress destructive verification")
        H.truthy(source:find("_backend_realm()", 1, true),
            "guard does not use stable backend realm metadata")
        H.truthy(source:find("_official_snapshot_present(self)", 1, true),
            "first-use official bootstrap is not distinguished from a destructive rewrite")
        H.truthy(source:find("_gut402_allow_verify_response", 1, true),
            "allowed first-use request does not bind its matching callback")
    end)

    H.test("issue 402 guard installs before the GUI entry body", function()
        local entry_path = repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/gui_tweaker_dev.lua"
        local file = assert(io.open(entry_path, "rb"))
        local source = file:read("*a")
        file:close()
        local guard = assert(source:find("_gut_official_loadout_boot_guard", 1, true))
        local ledger = assert(source:find("_lib_ui_presentation_refresh", 1, true))
        H.truthy(guard < ledger, "boot guard is not installed at the start of mod evaluation")
    end)

    H.test("issue 402 runtime imports a modded snapshot without verification", function()
        with_guard("modded", false, function(guard, hooks)
            H.equal(guard.in_modded_realm(), true,
                "stable backend metadata lost to transient false EAC flag")
            local seen_slots
            local mirror = { _characters_data_key = "characters_data" }
            hooks._set_inital_career_data(function(_, _, _, slots) seen_slots = slots end,
                mirror, "es_mercenary", { {} }, { "slot_melee" })
            H.truthy(type(seen_slots) == "table" and next(seen_slots) == nil,
                "destructive vanilla verification set reached snapshot import")
        end)
    end)

    H.test("issue 402 runtime blocks repair request and in-flight replacement", function()
        with_guard("modded", true, function(_, hooks)
            local vanilla_request, continued = 0, 0
            local mirror = {
                _characters_data_key = "characters_data",
                _num_items_to_load = 2,
                _verify_default_gear = function() continued = continued + 1 end,
            }
            hooks._fix_career_data(function() vanilla_request = vanilla_request + 1 end,
                mirror, { es_mercenary = {} }, nil, nil)
            H.equal(vanilla_request, 0)
            H.equal(continued, 1)
            hooks.fix_career_data_request_cb(function() vanilla_request = vanilla_request + 1 end,
                mirror, { FunctionResult = { num_items_granted = 0 } })
            H.equal(vanilla_request, 0)
            H.equal(mirror._num_items_to_load, 1)
            H.equal(continued, 2)
        end)
    end)

    H.test("issue 402 runtime pairs one missing-snapshot bootstrap", function()
        with_guard("modded", true, function(_, hooks)
            local requested, accepted, dlc = 0, 0, 0
            local mirror = {
                _characters_data_key = "characters_data",
                _characters_data = {},
                get_read_only_data = function() return nil end,
                _verify_dlc_careers = function() dlc = dlc + 1 end,
            }
            hooks._verify_career_loadouts(function() requested = requested + 1 end, mirror)
            H.equal(requested, 1)
            H.equal(mirror._gut402_allow_verify_response, true)
            hooks.verify_career_loadouts_cb(function() accepted = accepted + 1 end,
                mirror, { FunctionResult = { characters_data = "{}" } })
            H.equal(accepted, 1)
            H.equal(dlc, 0, "guard continued twice after accepted vanilla callback")
            H.equal(mirror._gut402_allow_verify_response, nil)
        end)
    end)

    H.test("issue 402 runtime blocks verify rewrites once a snapshot exists", function()
        with_guard("modded", true, function(_, hooks)
            local requested, accepted, dlc = 0, 0, 0
            local mirror = {
                _characters_data_key = "characters_data",
                _characters_data = { empire_soldier = {} },
                get_read_only_data = function() return "existing" end,
                _num_items_to_load = 1,
                _verify_dlc_careers = function() dlc = dlc + 1 end,
            }
            hooks._verify_career_loadouts(function() requested = requested + 1 end, mirror)
            hooks.verify_career_loadouts_cb(function() accepted = accepted + 1 end,
                mirror, { FunctionResult = { characters_data = "replacement" } })
            H.equal(requested, 0)
            H.equal(accepted, 0)
            H.equal(dlc, 2)
            H.equal(mirror._num_items_to_load, 0)
        end)
    end)

    H.test("issue 402 runtime leaves official and Versus boot vanilla", function()
        with_guard("official", true, function(_, hooks)
            local calls = 0
            local mirror = { _characters_data_key = "characters_data" }
            hooks._verify_career_loadouts(function() calls = calls + 1 end, mirror)
            H.equal(calls, 1)
        end)
        with_guard("modded", true, function(_, hooks)
            local calls = 0
            local mirror = { _characters_data_key = "vs_characters_data" }
            hooks._verify_career_loadouts(function() calls = calls + 1 end, mirror)
            H.equal(calls, 1)
        end)
    end)
end
