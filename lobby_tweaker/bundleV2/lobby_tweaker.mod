return {
    run = function()
        fassert(rawget(_G, "new_mod"), "Lobby Tweaker must be lower than Vermintide Mod Framework in the load order.")

        new_mod("lobby_tweaker", {
            mod_script       = "scripts/mods/lobby_tweaker/lobby_tweaker",
            mod_data         = "scripts/mods/lobby_tweaker/lobby_tweaker_data",
            mod_localization = "scripts/mods/lobby_tweaker/lobby_tweaker_localization",
        })
    end,
    packages = {
        "resource_packages/lobby_tweaker/lobby_tweaker",
    },
}
