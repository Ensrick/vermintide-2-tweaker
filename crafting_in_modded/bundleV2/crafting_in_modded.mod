return {
    run = function()
        fassert(rawget(_G, "new_mod"), "Crafting in Modded must be lower than Vermintide Mod Framework in the load order.")

        new_mod("cim", {
            mod_script       = "scripts/mods/crafting_in_modded/crafting_in_modded",
            mod_data         = "scripts/mods/crafting_in_modded/crafting_in_modded_data",
            mod_localization = "scripts/mods/crafting_in_modded/crafting_in_modded_localization",
        })
    end,
    packages = {
        "resource_packages/crafting_in_modded/crafting_in_modded",
    },
}
