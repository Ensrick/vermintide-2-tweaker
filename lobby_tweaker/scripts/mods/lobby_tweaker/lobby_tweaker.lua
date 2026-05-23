local mod = get_mod("lobby_tweaker")

mod.MOD_VERSION = "0.1.2-dev"
mod:echo("[Tweaker: Lobby] v" .. mod.MOD_VERSION .. " loaded.")

-- Phase 1: host-side lobby controls
mod:dofile("scripts/mods/lobby_tweaker/_slot_reservations")
mod:dofile("scripts/mods/lobby_tweaker/_session_ignore")
mod:dofile("scripts/mods/lobby_tweaker/_kick_idle")
mod:dofile("scripts/mods/lobby_tweaker/_motd")

-- Phase 2: modded-realm matchmaking
mod:dofile("scripts/mods/lobby_tweaker/_modded_manifest")
mod:dofile("scripts/mods/lobby_tweaker/_failed_join_reveal")

return mod
