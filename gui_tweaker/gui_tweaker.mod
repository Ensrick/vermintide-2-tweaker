return {
    run = function()
        fassert(rawget(_G, "new_mod"), "GUI Tweaker must be lower than Vermintide Mod Framework in the load order.")

        new_mod("gut", {
            mod_script       = "scripts/mods/gui_tweaker/gui_tweaker",
            mod_data         = "scripts/mods/gui_tweaker/gui_tweaker_data",
            mod_localization = "scripts/mods/gui_tweaker/gui_tweaker_localization",
        })
    end,
    packages = {
        "resource_packages/gui_tweaker/gui_tweaker",
    },
}
