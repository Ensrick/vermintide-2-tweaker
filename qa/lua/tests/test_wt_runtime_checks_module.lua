return function(H, repo_root)
    local public_root = repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/"
    local dev_root = repo_root .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/"

    local function install(root)
        local checks, commands = {}, {}
        local mod = {
            command = function(_, name)
                commands[#commands + 1] = name
            end,
        }
        dofile(root .. "_wt_runtime_checks.lua").install(mod, function(name, check)
            H.equal(type(check), "function")
            checks[#checks + 1] = name
        end, {})
        return checks, commands
    end

    H.test("WT common runtime-check extraction preserves beta registration surface", function()
        local checks, commands = install(public_root)
        H.equal(#checks, 50)
        H.equal(checks[1], "husk_extension_hooked")
        H.equal(checks[#checks], "wt_loc_raw_published")
        H.equal(#commands, 1)
        H.equal(commands[1], "verify_wt_availability_sort")
    end)

    H.test("WT dev runtime-check extraction keeps only its marked overlay additions", function()
        local checks, commands = install(dev_root)
        H.equal(#checks, 56)
        H.equal(checks[1], "husk_extension_hooked")
        H.equal(checks[#checks], "wt_loc_raw_published")
        H.equal(#commands, 1)
        H.equal(commands[1], "verify_wt_availability_sort")
    end)
end
