-- Pure umbrella-master policy for issue #221. No engine globals.
local M = {}

-- A default-ON feature master preserves every existing leaf configuration.
function M.enabled(master, leaf)
    return master ~= false and leaf == true
end

-- A default-OFF bulk ban composes with, rather than overwrites, individual bans.
function M.banned(master, leaf)
    return master == true or leaf == true
end

-- A default-ON numeric-family master returns vanilla semantics while disabled.
function M.value(master, configured, vanilla)
    if master == false then return vanilla end
    return configured
end

-- Final generated-item boundary. Vanilla unique archetypes bypass each weapon's
-- baked_trait_combinations, and the legacy empty-pool fallback deliberately
-- restores a non-empty pool. Filtering the detached result is therefore the
-- only complete, crash-safe owner for both individual bans and ban-all.
function M.filter_traits(master, traits, leaf_banned)
    if type(traits) ~= "table" then return traits, 0 end
    leaf_banned = leaf_banned or function() return false end
    local kept = {}
    local removed = 0
    for i = 1, #traits do
        local trait = traits[i]
        if M.banned(master, leaf_banned(trait)) then
            removed = removed + 1
        else
            kept[#kept + 1] = trait
        end
    end
    if removed == 0 then return traits, 0 end
    return kept, removed
end

return M
