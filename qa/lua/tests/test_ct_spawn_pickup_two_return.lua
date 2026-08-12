-- Cluster A regression (issue 322, class docs/BUG_CLASSES.md section 2): the CT
-- PickupSystem._spawn_pickup hook must preserve BOTH vanilla return values
-- (pickup_unit, pickup_unit_go_id) through EVERY branch. Vanilla returns the
-- pair at pickup_system.lua:1283 and the linked-pickup path feeds the go_id to
-- rpc_link_pickup (pickup_system.lua:1441-1447); collapsing to one value
-- desyncs surface-linked pickups on clients. The issue 294 non-resident guard
-- must stay a BARE return (= nil, nil to a 2-slot caller, matching vanilla's
-- own early returns at :1212-:1228).

return function(H, repo_root)
    local CTSource = dofile(repo_root .. "/qa/lua/ct_source.lua")
    local dir = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"

local function read(name)
        if tostring(name):find("chaos_wastes_tweaker_dev.lua", 1, true) then
            return CTSource.expanded(repo_root)
        end
        local file = assert(io.open(dir .. name, "rb"))
        local text = file:read("*a")
        file:close()
        return text
    end

    -- #1159: the hook moved verbatim from the entry into the pickup-spawn owner.
    -- The two-value contract is unchanged; the entry must hold no second copy.
    local source = read("_ct_pickup_spawn_owner.lua")
    local entry = read("chaos_wastes_tweaker_dev.lua")

    local HOOK_HEAD = 'mod:hook("PickupSystem", "_spawn_pickup"'

    H.test("CT _spawn_pickup hook is a singleton registration", function()
        local first = string.find(source, HOOK_HEAD, 1, true)
        H.truthy(first, "hook registration missing")
        H.equal(string.find(source, HOOK_HEAD, first + 1, true), nil,
            "second _spawn_pickup hook registration would be silently dropped by VMF")
        H.equal(string.find(entry, HOOK_HEAD, 1, true), nil,
            "the entry must not re-register the hook the owner now holds")
    end)

    -- Extract the hook body: from the registration to the issue 511 load-time
    -- marker planted directly after the hook's closing `end)`.
    local body_start = assert(string.find(source, HOOK_HEAD, 1, true))
    local marker_pos = assert(string.find(source, "CT_SPAWN_PICKUP322_MARKER", body_start, true),
        "issue 511 provenance marker vanished")
    local body = string.sub(source, body_start, marker_pos)

    H.test("CT _spawn_pickup captures and re-returns both vanilla values", function()
        H.truthy(string.find(body,
            "local spawned, go_id = func(self, settings, pickup_name, position, rotation, flag, spawn_type, ...)",
            1, true), "two-value capture line missing (issue 322 collapse reintroduced)")
        H.truthy(string.find(body, "return spawned, go_id", 1, true),
            "two-value return missing (issue 322 collapse reintroduced)")
    end)

    H.test("CT _spawn_pickup issue 294 guard stays a bare return", function()
        local guard = string.find(body, "if not mod._ct_pickup_unit_spawn_safe(settings) then", 1, true)
        H.truthy(guard, "issue 294 non-resident guard missing")
        local capture = assert(string.find(body, "local spawned, go_id = func(", guard, true))
        local guard_zone = string.sub(body, guard, capture)
        H.truthy(string.find(guard_zone, "\n%s+return%s*\n") ~= nil,
            "issue 294 early-return must stay BARE (nil, nil to the caller, matching vanilla)")
    end)

    H.test("CT _spawn_pickup hook has no value-returning branch besides the pair", function()
        -- Statement-position `return`s inside the body: exactly the bare issue
        -- 294 return and the final `return spawned, go_id`. A third return would
        -- be a new branch that must be audited for the two-value contract.
        local returns = {}
        for line in string.gmatch(body, "[^\n]*") do
            local stmt = string.match(line, "^%s*(return[^\n]*)")
            if stmt then returns[#returns + 1] = stmt end
        end
        H.equal(#returns, 2, "unexpected return-statement count in _spawn_pickup hook body")
        H.equal(returns[1]:gsub("%s+$", ""), "return")
        H.truthy(string.find(returns[2], "return spawned, go_id", 1, true) == 1)
    end)

    H.test("CT _spawn_pickup marker pins the two-return fix version", function()
        H.truthy(string.find(source,
            'CT_SPAWN_PICKUP322_MARKER = "spawn_pickup322:two_value_capture_and_return_v0.7.245"',
            1, true), "marker string drifted; update the rt check and this test together")
    end)
end
