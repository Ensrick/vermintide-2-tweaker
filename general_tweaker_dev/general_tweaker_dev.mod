return {
    run = function()
        fassert(rawget(_G, "new_mod"), "General Tweaker must be lower than Vermintide Mod Framework in the load order.")

        new_mod("gt_dev", {
            mod_script       = "scripts/mods/general_tweaker_dev/general_tweaker_dev",
            mod_data         = "scripts/mods/general_tweaker_dev/general_tweaker_dev_data",
            mod_localization = "scripts/mods/general_tweaker_dev/general_tweaker_dev_localization",
        })
    end,
    packages = {
        "resource_packages/general_tweaker_dev/general_tweaker_dev",
    },
}
