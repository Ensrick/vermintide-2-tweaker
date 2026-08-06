-- Behavior-neutral balance-catalog composition owner for Phase 5 (#1159/#504/#2).
-- Each bounded catalog module returns disjoint definitions; this owner merges them
-- once before the unchanged apply/restore engine consumes the resulting table.

local function build(ctx)
    assert(type(ctx) == "table", "crt balance catalog context required")
    local mod = assert(ctx.mod, "crt balance catalog mod required")
    assert(ctx.wire_policy, "crt balance catalog wire_policy required")
    assert(ctx.make_stub, "crt balance catalog make_stub required")
    assert(ctx.ensure_wire_safe_funcs, "crt balance catalog wire helper required")
    assert(ctx.min_thp_on_kill, "crt balance catalog THP floor required")

    local build_early = mod:dofile("scripts/mods/career_tweaker/_crt_balance_catalog_early")
    local build_late = mod:dofile("scripts/mods/career_tweaker/_crt_balance_catalog_late")
    local result = build_early(ctx)

    for setting_id, definition in pairs(build_late(ctx)) do
        assert(result[setting_id] == nil, "duplicate CRT balance definition: " .. tostring(setting_id))
        result[setting_id] = definition
    end

    return result
end

return build
