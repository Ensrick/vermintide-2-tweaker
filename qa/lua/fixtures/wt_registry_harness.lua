-- WP-WT-07: build the production mutation registry for host harnesses that
-- boot wt modules without the entry file. It uses the real
-- _wt_mutation_registry.lua and the real owner table _wt_mutation_owners.lua,
-- so a harness exercises the same owners in the same order as the game.
--
-- usage: local reg = dofile(<repo>/qa/lua/fixtures/wt_registry_harness.lua)(module_dir, mod, deps, log)
--   module_dir ends with "/", e.g. <repo>/weapon_tweaker/scripts/mods/weapon_tweaker/
--   deps = the entry handles (apply_weapon_unlocks, clear_weapon_unlocks,
--          patch_career_actions, clear_career_actions, history_owner, bolt_runtime)
return function(module_dir, mod, deps, log)
    local registry = dofile(module_dir .. "_wt_mutation_registry.lua")
    local owners = dofile(module_dir .. "_wt_mutation_owners.lua")
    local reg = registry.new(log or function() end)
    owners.register(reg, mod, deps or {})
    return reg
end
