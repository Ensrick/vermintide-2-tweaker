-- _cim_craft_dispatch.lua -- final local synth dispatch contract.
--
-- Synth functions return (public_result, committed?). Legacy synths omit the
-- second value and remain successful by default. A refused transaction returns
-- committed=false: the craft request still completes with its public-compatible
-- result, but presentation caches are not invalidated.
-- Owned by standard_forge.lua and loaded through mod:dofile.

local M = {
    MARKER = "cim_craft_dispatch_v1",
}

function M.execute(deps, crafting, synth_fn, item_backend_ids, recipe, recipe_override)
    deps = type(deps) == "table" and deps or {}
    assert(type(crafting) == "table"
        and type(crafting._craft_requests) == "table")
    assert(type(synth_fn) == "function")

    crafting._last_id = (crafting._last_id or 0) + 1
    local id = crafting._last_id
    local result, committed = synth_fn(
        crafting, item_backend_ids, recipe, recipe_override)
    committed = committed ~= false
    crafting._craft_requests[id] = result or {}

    if committed and type(deps.invalidate) == "function" then
        pcall(deps.invalidate)
    end
    return id, recipe, committed
end

return M
