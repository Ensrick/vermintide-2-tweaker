-- Pure policy for #304. Kept engine-free so the exact keep/dummy scope can be
-- exercised under the repository's offline Lua 5.1 harness.
local Policy = {}

function Policy.is_training_dummy(breed)
    return type(breed) == "table" and breed.name == "training_dummy"
end

function Policy.should_remove_player_constraint(enabled, is_in_inn, breed)
    return enabled == true and is_in_inn == true and Policy.is_training_dummy(breed)
end

return Policy
