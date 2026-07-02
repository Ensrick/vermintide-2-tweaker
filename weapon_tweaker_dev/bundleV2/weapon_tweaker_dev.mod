return {
    run = function()
        fassert(rawget(_G, "new_mod"), "Weapon Tweaker must be lower than Vermintide Mod Framework in the load order.")

        new_mod("wt_dev", {
            mod_script       = "scripts/mods/weapon_tweaker_dev/weapon_tweaker_dev",
            mod_data         = "scripts/mods/weapon_tweaker_dev/weapon_tweaker_dev_data",
            mod_localization = "scripts/mods/weapon_tweaker_dev/weapon_tweaker_dev_localization",
        })
    end,
    packages = {
        "resource_packages/weapon_tweaker_dev/weapon_tweaker_dev",
    },
}
