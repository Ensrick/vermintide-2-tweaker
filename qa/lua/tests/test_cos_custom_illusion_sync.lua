return function(H, repo_root)
    local chunk = assert(loadfile(repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_custom_illusion_sync.lua"))
    local policy = chunk()

    local custom = { ct_spear = true }
    local item_master = {
        ct_spear = {
            matching_item_key = "es_2h_heavy_spear",
            template = "spear_template",
            right_hand_unit = "custom/spear",
        },
    }
    local skins = {
        ct_spear = {
            template = "spear_template",
            right_hand_unit = "custom/spear",
        },
    }

    H.test("Cosmetics #918 resolves an exact custom-illusion family", function()
        local template, hands, reason, backend_id = policy.resolve(
            custom, item_master, skins,
            {
                key = "provider-instance-key",
                backend_id = "bid-1",
                data = { name = "es_2h_heavy_spear", template = "spear_template" },
            }, "ct_spear")
        H.equal(template, "spear_template")
        H.equal(hands.right_hand_unit, "custom/spear")
        H.equal(hands.left_hand_unit, nil)
        H.equal(reason, "exact-family")
        H.equal(backend_id, "bid-1")
    end)

    H.test("Cosmetics #918 rejects a custom skin from the wrong weapon family", function()
        local _, hands, reason = policy.resolve(custom, item_master, skins,
            { key = "es_1h_sword", template = "sword_template" }, "ct_spear")
        H.equal(hands, nil)
        H.equal(reason, "wrong-family")
    end)

    H.test("Cosmetics #918 degrades a missing custom definition to base appearance", function()
        local template, hands, reason = policy.resolve(custom, {}, skins,
            { data = { name = "es_2h_heavy_spear", template = "spear_template" } },
            "ct_spear")
        H.equal(template, "spear_template")
        H.equal(hands, nil)
        H.equal(reason, "missing-definition")
    end)

    H.test("Cosmetics #918 plan replays desired hands and clears removed hands", function()
        local operations, next_state = policy.plan(
            { right_hand_unit = "old/right", left_hand_unit = "old/left" },
            { right_hand_unit = "new/right" })
        H.equal(#operations, 2)
        H.equal(operations[1].hand, "right_hand_unit")
        H.equal(operations[1].unit, "new/right")
        H.equal(operations[2].hand, "left_hand_unit")
        H.equal(operations[2].unit, "")
        H.equal(next_state.right_hand_unit, "new/right")
        H.equal(next_state.left_hand_unit, nil)
    end)

    H.test("Cosmetics #918 leaves exact per-instance hand selections untouched", function()
        local operations, next_state = policy.plan(
            { right_hand_unit = "old/right", left_hand_unit = "old/left" },
            { right_hand_unit = "skin/right", left_hand_unit = "skin/left" },
            { left_hand_unit = true })
        H.equal(#operations, 1)
        H.equal(operations[1].hand, "right_hand_unit")
        H.equal(operations[1].unit, "skin/right")
        H.equal(next_state.right_hand_unit, "skin/right")
        H.equal(next_state.left_hand_unit, nil)
    end)

    H.test("Cosmetics #918 runtime adapter publishes through the existing hand sender", function()
        local sent, owner = {}, {}
        H.truthy(policy.install(owner, {
            custom_skin_keys = custom,
            item_master = item_master,
            weapon_skins = skins,
            unit_alive = function() return true end,
            owner_for_unit = function() return { peer_id = "peer-a" } end,
            wearer_is_human = function() return true end,
            selection_for = function() return nil end,
            send = function(unit, template, hand, path)
                sent[#sent + 1] = { unit, template, hand, path }
            end,
        }))
        local applied, reason, count = owner._cos_send_custom_skin_hands(
            "unit-a", { key = "es_2h_heavy_spear" }, "ct_spear", "test")
        H.equal(applied, true)
        H.equal(reason, "exact-family")
        H.equal(count, 1)
        H.equal(sent[1][2], "spear_template")
        H.equal(sent[1][3], "right_hand_unit")
        H.equal(sent[1][4], "custom/spear")
    end)

    H.test("Cosmetics #918 runtime adapter fails open on dependency errors", function()
        local owner = {}
        H.truthy(policy.install(owner, {
            custom_skin_keys = custom,
            item_master = item_master,
            weapon_skins = skins,
            unit_alive = function() error("synthetic unit failure") end,
            owner_for_unit = function() return { peer_id = "peer-a" } end,
            wearer_is_human = function() return true end,
            selection_for = function() return nil end,
            send = function() error("must not send") end,
            log = function() end,
        }))
        local ok, applied, reason, count = pcall(
            owner._cos_send_custom_skin_hands,
            "unit-a", { key = "es_2h_heavy_spear" }, "ct_spear", "test")
        H.equal(ok, true)
        H.equal(applied, false)
        H.equal(reason, "publish-error")
        H.equal(count, 0)
    end)

    H.test("Cosmetics #918 production owns a runtime check and existing transport", function()
        local function read(path)
            local file = assert(io.open(path, "rb"))
            local value = file:read("*a")
            file:close()
            return value
        end
        local base = repo_root .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
        local runtime = read(base .. "_cos_runtime_checks.lua")
        local entry = read(base .. "cosmetics_tweaker.lua")
        local wire = read(base .. "_cos_wire.lua")
        H.truthy(runtime:find(
            '_rt_register("issue918_custom_illusion_semantic_sync"', 1, true))
        H.truthy(entry:find("custom_illusion_sync = CUSTOM_ILLUSION_SYNC", 1, true))
        H.truthy(entry:find("send = mod._send_offhand_mesh", 1, true))
        H.truthy(wire:find('"game_object_initialized"', 1, true))
        H.truthy(wire:find('"spawn_resynced_loadout"', 1, true))
        H.truthy(wire:find('"hot_join_sync"', 1, true))
        H.equal(read(base .. "_cos_custom_illusion_sync.lua"):find(
            "network_register", 1, true), nil)
    end)
end
