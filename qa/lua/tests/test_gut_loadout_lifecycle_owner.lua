return function(H, repo_root)
    local owner_path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_loadout_lifecycle_owner.lua"
    local Owner = assert(loadfile(owner_path))()
    local policy_path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_native_loadout_policy.lua"
    local Policy = assert(loadfile(policy_path))()

    local function capture(overrides)
        local writes = overrides.writes or {}
        local ctx = {
            mode = overrides.mode or Policy.MODE_STORE,
            mode_off = Policy.MODE_OFF,
            career_name = "es_mercenary",
            backend_id = "transient_backend_id",
            slot_name = overrides.slot_name or "slot_hat",
            is_loadout_slot = overrides.is_loadout_slot ~= false,
            capture_slot_durable = Policy.capture_slot_durable,
            slot_owned_by_items = overrides.slot_owned_by_items or function() return true end,
            get_mirror = overrides.get_mirror or function() return { durable = true } end,
            canonical_value = overrides.canonical_value or function(backend_id, slot_name)
                local item = rawget(overrides, "item")
                if item == nil then item = { ItemId = "hat_master_key" } end
                return Policy.canonical_equip_value(slot_name, backend_id, item)
            end,
            write = overrides.write or function(mode, mirror, career, slot, value, source)
                writes[#writes + 1] = { mode, mirror, career, slot, value, source }
            end,
        }
        local result, reason = Owner.capture_equip(ctx)
        return result, reason, writes
    end

    H.test("#353 outer owner captures every canonical cosmetic in store and readonly modes", function()
        local cases = {
            { "slot_skin", { override_id = "skin_override", ItemId = "skin_key" }, "skin_override" },
            { "slot_hat", { ItemId = "hat_key" }, "hat_key" },
            { "slot_frame", { ItemId = "frame_key" }, "frame_key" },
            { "slot_pose", { ItemId = "pose_key" }, "pose_key" },
        }
        for _, mode in ipairs({ Policy.MODE_STORE, Policy.MODE_READONLY }) do
            for _, case in ipairs(cases) do
                local writes = {}
                local result = capture({
                    mode = mode, slot_name = case[1], item = case[2], writes = writes,
                })
                H.equal(result, "captured")
                H.equal(#writes, 1)
                H.equal(writes[1][1], mode)
                H.equal(writes[1][3], "es_mercenary")
                H.equal(writes[1][4], case[1])
                H.equal(writes[1][5], case[3])
            end
        end
    end)

    H.test("#353 outer owner rejects unresolved cosmetics and foreign run-local gear", function()
        local writes = {}
        local unresolved = capture({ item = false, writes = writes })
        H.equal(unresolved, "unresolved")
        H.equal(#writes, 0)
        local foreign = capture({
            slot_name = "slot_melee", writes = writes,
            slot_owned_by_items = function() return false end,
            canonical_value = function(id) return id, "backend_id" end,
        })
        H.equal(foreign, "foreign-owner")
        H.equal(#writes, 0)
    end)

    H.test("#353 outer owner contains mirror, registry, and writer failures", function()
        local mirror = capture({ get_mirror = function() error("mirror") end })
        H.equal(mirror, "unresolved")
        local registry = capture({ canonical_value = function() error("registry") end })
        H.equal(registry, "unresolved")
        local writer = capture({ write = function() error("writer") end })
        H.equal(writer, "write-error")
    end)

    H.test("#354 lifecycle owner drives exactly the three bounded persistence edges", function()
        local edges, previous = {}, {}
        local on_state, on_unload = Owner.bind_snapshot_edges({
            snapshot = function(edge) edges[#edges + 1] = edge end,
            previous_state = function(status, state) previous[#previous + 1] = status .. ":" .. state end,
            previous_unload = function(value) previous[#previous + 1] = "unload:" .. value end,
        })
        on_state("enter", "StateIngame")
        on_state("exit", "StateIngame")
        on_state("enter", "StateTitleScreen")
        on_state("exit", "StateTitleScreen")
        on_unload("sentinel")
        H.equal(table.concat(edges, ","), "ingame_exit,title_enter,unload")
        H.equal(#previous, 5, "every previous callback must remain chained")
        H.equal(previous[5], "unload:sentinel")
    end)

    H.test("#354 lifecycle owner contains and reports snapshot and prior-callback failures", function()
        local reports = {}
        local on_state, on_unload = Owner.bind_snapshot_edges({
            snapshot = function(edge) error("snapshot:" .. edge) end,
            previous_state = function() error("previous-state") end,
            previous_unload = function() error("previous-unload") end,
            report_error = function(edge) reports[#reports + 1] = edge end,
        })
        H.truthy(pcall(on_state, "exit", "StateIngame"))
        H.truthy(pcall(on_unload))
        H.equal(table.concat(reports, ","),
            "previous_state,ingame_exit,previous_unload,unload")
    end)
end
