return {
    run = function()
        fassert(rawget(_G, "new_mod"), "`chaos_wastes_coin_tweaker` mod loaded before VMF.")

        new_mod("chaos_wastes_coin_tweaker", {
            mod_script       = "scripts/mods/chaos_wastes_coin_tweaker/chaos_wastes_coin_tweaker",
            mod_data         = "scripts/mods/chaos_wastes_coin_tweaker/chaos_wastes_coin_tweaker_data",
            mod_localization = "scripts/mods/chaos_wastes_coin_tweaker/chaos_wastes_coin_tweaker_localization",
        })
    end,
    packages = {
        "resource_packages/chaos_wastes_coin_tweaker",
    },
}
