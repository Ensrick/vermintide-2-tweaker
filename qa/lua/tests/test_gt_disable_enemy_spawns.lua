-- Locks the #242 Disable Enemy Spawns design:
--   1. NIL-SAFETY: the spawn refusal must NOT live in spawn_queued_unit.
--      Vanilla consumers use the returned spawn-queue id as a table key
--      (bt_chaos_sorcerer_summoning_action.lua:406-408) and hand it back to
--      remove_queued_unit, which ferror()s on unknown ids
--      (conflict_director.lua:1832). The block parks the queue at the
--      update_spawn_queue drain instead, so every consumer holds a REAL id.
--   2. PICKUP PASSTHROUGH: spawn_unit_immediate's only vanilla callers are
--      the training-dummy pickups (pickups.lua:147/179, category "pickup");
--      only AI enemy spawns may be refused there.
-- Behavioral cases extract the shipped hook closures from the mod source and
-- execute them against stub ConflictDirector/consumer patterns.
return function(H, repo_root)
    local path = repo_root .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/general_tweaker_dev.lua"
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()

    -- Extract one mod:hook("ConflictDirector", "<method>", ...) statement,
    -- from its opening call through the unindented terminating `end)`.
    local function extract_hook_snippet(method)
        local needle = 'mod:hook("ConflictDirector", "' .. method .. '"'
        local start = source:find(needle, 1, true)
        if not start then
            return nil, "hook registration not found: " .. method
        end
        local term = source:find("\nend)", start, true)
        if not term then
            return nil, "hook terminator not found: " .. method
        end
        return source:sub(start, term + #"\nend)" - 1)
    end

    -- Compile the snippet standalone. `mod` resolves through the sandbox env
    -- to a stub whose :hook captures the registered closure.
    local function capture_hook(method, settings, mod_overrides)
        local snippet, err = extract_hook_snippet(method)
        H.truthy(snippet, err)
        local captured
        local stub_mod = {
            get = function(_, id) return settings[id] end,
            hook = function(_, _, _, fn) captured = fn end,
            info = function() end,
        }
        for key, value in pairs(mod_overrides or {}) do
            stub_mod[key] = value
        end
        local env = setmetatable({ mod = stub_mod }, { __index = _G })
        local chunk = assert(loadstring(snippet, "@gt_242_" .. method))
        setfenv(chunk, env)
        chunk()
        H.truthy(captured, "hook closure was not registered: " .. method)
        return captured, stub_mod
    end

    H.test("GT #242 hooks cover queue drain, enqueue, and immediate spawn", function()
        H.truthy(source:find('mod:hook("ConflictDirector", "spawn_queued_unit"', 1, true))
        H.truthy(source:find('mod:hook("ConflictDirector", "update_spawn_queue"', 1, true))
        H.truthy(source:find('mod:hook("ConflictDirector", "spawn_unit_immediate"', 1, true))
    end)

    H.test("GT #242 spawn_queued_unit hook contains no refusal (nil-key crash class)", function()
        local snippet = assert(extract_hook_snippet("spawn_queued_unit"))
        -- The refusal returning nil from spawn_queued_unit is the latent
        -- crash: vortex_data.queued_vortex[nil] = {...} at
        -- bt_chaos_sorcerer_summoning_action.lua:408. The hook body may
        -- MENTION the setting in comments but must never gate on it.
        for line in snippet:gmatch("[^\n]+") do
            local code = line:gsub("%-%-.*$", "")
            H.truthy(not code:find("disable_enemy_spawns", 1, true),
                "spawn_queued_unit hook must not gate on disable_enemy_spawns: " .. line)
        end
        -- Consumer citation must stay with the design so the invariant is
        -- rediscoverable.
        H.truthy(source:find("bt_chaos_sorcerer_summoning_action.lua:406-408", 1, true))
        H.truthy(source:find("remove_queued_unit", 1, true))
    end)

    H.test("GT #242 blocked spawn_queued_unit still yields a real usable queue id", function()
        local settings = { disable_enemy_spawns = true }
        local hook_fn = capture_hook("spawn_queued_unit", settings)
        -- Mock the vanilla enqueue contract (conflict_director.lua:1732-1791,
        -- simplified): allocate the next id, record the entry, return the id.
        local director = { spawn_queue_id = 7, queue = {} }
        local vanilla = function(self, breed)
            self.spawn_queue_id = self.spawn_queue_id + 1
            self.queue[self.spawn_queue_id] = breed
            return self.spawn_queue_id
        end
        local id = hook_fn(vanilla, director, { name = "chaos_vortex_sorcerer" })
        H.equal(id, 8, "hook must pass the vanilla queue id through even while blocked")
        -- Chaos Sorcerer consumer pattern: nil id here is the shipped crash.
        local queued_vortex = {}
        local ok = pcall(function() queued_vortex[id] = { decal = true } end)
        H.truthy(ok, "spawn id must be usable as a table key")
        -- Death-cleanup pattern (ai_breed_snippets.lua:900-901): the id must
        -- name a real queue entry or remove_queued_unit ferror()s.
        H.truthy(director.queue[id] ~= nil, "refused spawn must remain a real queue entry")
    end)

    H.test("GT #242 dequeue gate parks the queue while blocked and drains when clear", function()
        local settings = { disable_enemy_spawns = true }
        local hook_fn, stub_mod = capture_hook("update_spawn_queue", settings)
        local drained = 0
        local vanilla = function() drained = drained + 1 end
        hook_fn(vanilla, {})
        H.equal(drained, 0, "toggle on must park the queue")
        settings.disable_enemy_spawns = false
        stub_mod._gt_freeze_ai_active = true
        hook_fn(vanilla, {})
        H.equal(drained, 0, "Freeze AI must park the queue")
        stub_mod._gt_freeze_ai_active = nil
        hook_fn(vanilla, {})
        H.equal(drained, 1, "clear state must drain vanilla")
    end)

    H.test("GT #242 spawn_unit_immediate passes pickups and refuses AI enemies", function()
        local settings = { disable_enemy_spawns = true }
        local hook_fn = capture_hook("spawn_unit_immediate", settings)
        local calls = 0
        local vanilla = function() calls = calls + 1; return "unit", 42 end
        -- Training-dummy pickup route (pickups.lua:147/179): must pass.
        local unit, go_id = hook_fn(vanilla, {}, { name = "training_dummy", race = "dummy" },
            "pos", "rot", "pickup")
        H.equal(unit, "unit", "pickup-category spawn must pass through while blocked")
        H.equal(go_id, 42, "go_id must propagate")
        -- Dummy race belt-and-suspenders (breed_training_dummy.lua:43).
        unit = hook_fn(vanilla, {}, { name = "training_dummy", race = "dummy" },
            "pos", "rot", nil)
        H.equal(unit, "unit", "dummy-race spawn must pass through while blocked")
        -- AI enemy immediate spawn: refused, vanilla untouched.
        unit, go_id = hook_fn(vanilla, {}, { name = "skaven_storm_vermin", race = "skaven" },
            "pos", "rot", "terror_event")
        H.equal(unit, nil, "AI enemy immediate spawn must be refused while blocked")
        H.equal(go_id, nil)
        H.equal(calls, 2, "refusal must not reach vanilla")
        -- Toggle off: everything passes.
        settings.disable_enemy_spawns = false
        unit = hook_fn(vanilla, {}, { name = "skaven_storm_vermin", race = "skaven" },
            "pos", "rot", "terror_event")
        H.equal(unit, "unit", "toggle off must restore vanilla enemy spawns")
    end)

    H.test("GT #242 drives every native spawn producer gate", function()
        local flags = {
            "ai_mini_patrol_disabled",
            "ai_boss_spawning_disabled",
            "ai_horde_spawning_disabled",
            "ai_roaming_spawning_disabled",
            "ai_specials_spawning_disabled",
            "ai_critter_spawning_disabled",
        }
        for _, name in ipairs(flags) do
            H.truthy(source:find('"' .. name .. '"', 1, true), name)
        end
        H.truthy(source:find('issue242_all_spawn_classes_blocked', 1, true))
    end)

    H.test("GT #242 regression check locks the dequeue-gate and passthrough markers", function()
        H.truthy(source:find("mod._gt_242_dequeue_gate_armed = true", 1, true))
        H.truthy(source:find("mod._gt_242_pickup_passthrough_armed = true", 1, true))
        H.truthy(source:find('"update_spawn_queue dequeue gate not armed"', 1, true))
        H.truthy(source:find('"spawn_unit_immediate pickup passthrough not armed"', 1, true))
    end)

    H.test("GT #242 block is reversible and preserves existing enemies", function()
        H.truthy(source:find("script_data[name] = block or nil", 1, true))
        H.truthy(source:find("Existing enemies are NOT despawned", 1, true))
    end)
end
