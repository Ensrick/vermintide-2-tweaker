-- Cluster B regression (issues 249 / 256 / 289): drives the pure ammo
-- grant/clamp kernel (_ct_ammo_guard_core.lua) and pins the live wiring in
-- _ct_meta_trait_boons.lua textually - the server-authoritative stack grant
-- (host adds via BuffSystem server-controlled path, replicated to clients per
-- buff_system.lua:277-311; clients defer), the issue 426 parity gate, and the
-- issue 256 [0, max] consumption-side clamp that never touches _max_ammo.

return function(H, repo_root)
    local core_path = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
        .. "_ct_ammo_guard_core.lua"
    local Core = assert(loadfile(core_path))()

    H.test("CT ammo grant_plan decision matrix", function()
        local cases = {
            { true,  true,  0, 5, "networked", 5 },
            { true,  true,  3, 5, "networked", 2 },
            { true,  false, 0, 5, "local",     5 },
            { false, true,  0, 5, "defer_to_server", 0 },
            { false, false, 2, 5, "defer_to_server", 0 },
            { true,  true,  5, 5, "none", 0 },
            { true,  true,  7, 5, "none", 0 },
            { false, true,  5, 5, "none", 0 },
            { true,  true,  nil, 3, "networked", 3 },
            { true,  true,  2, nil, "none", 0 },
        }
        for i, c in ipairs(cases) do
            local mode, n = Core.grant_plan(c[1], c[2], c[3], c[4])
            H.equal(mode, c[5], "case " .. i .. " mode")
            H.equal(n, c[6], "case " .. i .. " count")
        end
    end)

    H.test("CT ammo clamp_value stays in [0, max] and reports change", function()
        local v, changed = Core.clamp_value(20, -4)
        H.equal(v, 0); H.equal(changed, true)
        v, changed = Core.clamp_value(20, 25)
        H.equal(v, 20); H.equal(changed, true)
        v, changed = Core.clamp_value(20, 12)
        H.equal(v, 12); H.equal(changed, false)
        v, changed = Core.clamp_value(nil, -3)   -- unknown max: floor only
        H.equal(v, 0); H.equal(changed, true)
        v, changed = Core.clamp_value(nil, 1e6)  -- unknown max: no ceiling
        H.equal(v, 1e6); H.equal(changed, false)
        v, changed = Core.clamp_value(20, "not_a_number")
        H.equal(v, "not_a_number"); H.equal(changed, false)
    end)

    local meta_path = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
        .. "_ct_meta_trait_boons.lua"
    local file = assert(io.open(meta_path, "rb"))
    local meta_src = file:read("*a")
    file:close()

    H.test("CT meta-boon grant is server-authoritative and parity-gated", function()
        H.truthy(string.find(meta_src,
            "local mode, n = AmmoGuardCore.grant_plan(is_server, wire_safe, num_existing, stacks_target)",
            1, true), "proc no longer routes through the pure grant kernel")
        H.truthy(string.find(meta_src,
            "buff_system:add_buff(unit, stack_name, unit, true)", 1, true),
            "server-controlled BuffSystem add missing (issue 249/289 fix reverted)")
        H.truthy(string.find(meta_src,
            "local wire_safe = mod._ct_wire_safe and mod._ct_wire_safe() == true", 1, true),
            "issue 426 parity gate not consulted before the networked grant")
        H.truthy(string.find(meta_src,
            "CT_META_AMMO_SERVER_AUTH_MARKER = AmmoGuardCore.MARKER", 1, true),
            "server-auth marker assignment missing")
        H.equal(Core.MARKER, "meta_ammo:server_authoritative_stack_grant_v0.7.298")
    end)

    H.test("CT issue 256 clamp routes through the pure kernel, never _max_ammo", function()
        H.truthy(string.find(meta_src,
            "AmmoGuardCore.clamp_value(max_ammo, ax._available_ammo)", 1, true))
        H.truthy(string.find(meta_src,
            "AmmoGuardCore.clamp_value(max_ammo, ax._current_ammo)", 1, true))
        -- The clamp wrapper must not assign into _max_ammo (max-resource
        -- doctrine: consumption-side only).
        local wrapper_start = assert(string.find(meta_src,
            "local function _ct_clamp_current_ammo_256", 1, true))
        local wrapper_end = assert(string.find(meta_src,
            "mod._ct_clamp_current_ammo_256 = _ct_clamp_current_ammo_256", wrapper_start, true))
        local wrapper = string.sub(meta_src, wrapper_start, wrapper_end)
        H.equal(string.find(wrapper, "ax._max_ammo%s*="), nil,
            "clamp wrapper writes _max_ammo - max-resource doctrine violation")
    end)
end
