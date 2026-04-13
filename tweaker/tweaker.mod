return {
    run = function()
        fassert(rawget(_G, "new_mod"), "`tweaker` mod loaded before VMF.")

        new_mod("t", {
            mod_script       = "scripts/mods/tweaker/tweaker",
            mod_data         = "scripts/mods/tweaker/tweaker_data",
            mod_localization = "scripts/mods/tweaker/tweaker_localization",
        })
    end,
    packages = {
        "resource_packages/tweaker",
    },
}
