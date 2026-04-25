return {
    run = function()
        fassert(rawget(_G, "new_mod"), "General Tweaker must be lower than Vermintide Mod Framework in the load order.")

        new_mod("gt", {
            mod_script       = "scripts/mods/general_tweaker/general_tweaker",
            mod_data         = "scripts/mods/general_tweaker/general_tweaker_data",
            mod_localization = "scripts/mods/general_tweaker/general_tweaker_localization",
        })
    end,
    packages = {
        "resource_packages/general_tweaker",
    },
}
