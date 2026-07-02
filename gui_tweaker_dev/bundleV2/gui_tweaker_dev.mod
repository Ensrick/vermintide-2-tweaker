return {
    run = function()
        fassert(rawget(_G, "new_mod"), "GUI Tweaker dev must be lower than Vermintide Mod Framework in the load order.")

        new_mod("gut_dev", {
            mod_script       = "scripts/mods/gui_tweaker_dev/gui_tweaker_dev",
            mod_data         = "scripts/mods/gui_tweaker_dev/gui_tweaker_dev_data",
            mod_localization = "scripts/mods/gui_tweaker_dev/gui_tweaker_dev_localization",
        })
    end,
    packages = {
        "resource_packages/gui_tweaker_dev/gui_tweaker_dev",
    },
}
