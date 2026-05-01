return {
    run = function()
        fassert(rawget(_G, "new_mod"), "Weapon Tweaker must be lower than Vermintide Mod Framework in the load order.")

        new_mod("wt", {
            mod_script       = "scripts/mods/weapon_tweaker/weapon_tweaker",
            mod_data         = "scripts/mods/weapon_tweaker/weapon_tweaker_data",
            mod_localization = "scripts/mods/weapon_tweaker/weapon_tweaker_localization",
        })
    end,
    packages = {
        "resource_packages/weapon_tweaker/weapon_tweaker",
    },
}
