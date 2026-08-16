-- Behavioral coverage for _gut_reset_presentation_core.lua (issue #1033): the pure
-- plan that reconciles the active career's live presentation after an Equipment
-- DEFAULT reset. Drives the real shipped file; no source pinning.
return function(H, repo_root)
    local path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_reset_presentation_core.lua"
    local Core = assert(loadfile(path))()

    H.test("issue 1033 slot routes mirror the vanilla presentation dispatch", function()
        -- hero_view_state_overview.lua:706-712 (equip request dispatch) and
        -- :1157-1161 (skin sync -> IngameUI:respawn).
        local want = {
            slot_melee = Core.ROUTE_INVENTORY,
            slot_ranged = Core.ROUTE_INVENTORY,
            slot_hat = Core.ROUTE_ATTACHMENT,
            slot_necklace = Core.ROUTE_ATTACHMENT,
            slot_ring = Core.ROUTE_ATTACHMENT,
            slot_trinket_1 = Core.ROUTE_ATTACHMENT,
            slot_skin = Core.ROUTE_RESPAWN,
            slot_frame = Core.ROUTE_NONE,
            slot_pose = Core.ROUTE_NONE,
        }
        for slot, route in pairs(want) do
            H.equal(Core.SLOT_ROUTES[slot], route, "route for " .. slot)
        end
        for slot in pairs(Core.SLOT_ROUTES) do
            H.truthy(want[slot] ~= nil, "unexpected routed slot " .. slot)
        end
        -- Every equip-walk slot must route through a live extension path.
        for _, slot in ipairs(Core.EQUIP_SLOTS) do
            local route = Core.SLOT_ROUTES[slot]
            H.truthy(route == Core.ROUTE_INVENTORY or route == Core.ROUTE_ATTACHMENT,
                "equip slot " .. slot .. " has non-extension route")
        end
    end)

    H.test("issue 1033 respawn fires only on a proven skin ownership change", function()
        H.equal(Core.skin_changed("skin_a", "skin_b"), true)
        H.equal(Core.skin_changed("skin_a", "skin_a"), false)
        -- A failed read is "unknown", never a respawn trigger.
        H.equal(Core.skin_changed(nil, "skin_b"), false)
        H.equal(Core.skin_changed("skin_a", nil), false)
        H.equal(Core.skin_changed(nil, nil), false)
    end)

    H.test("issue 1033 reconcile defers anywhere but a live keep unit", function()
        H.equal(Core.should_defer(true, true), false)
        H.equal(Core.should_defer(true, false), true)   -- keep, no unit yet
        H.equal(Core.should_defer(false, true), true)   -- mission-side stays durable
        H.equal(Core.should_defer(false, false), true)
        H.equal(Core.should_defer(nil, nil), true)
    end)

    H.test("issue 1033 plan re-equips exactly the changed live slots", function()
        local desired = {
            slot_melee = "ID_M", slot_ranged = "ID_R", slot_hat = "ID_H",
            slot_necklace = "ID_N",
        }
        local keys = {
            slot_melee = "k_m", slot_ranged = "k_r", slot_hat = "k_h",
            slot_necklace = "k_n",
        }
        -- Live unit still wears the pre-reset melee and hat; ranged already matches;
        -- necklace live-empty (the reset restored the official necklace).
        local live_id = { slot_melee = "OLD_M", slot_ranged = "ID_R", slot_hat = "OLD_H" }
        local plan = Core.plan(desired, keys, live_id, {})
        H.equal(#plan.actions, 3)
        H.equal(plan.actions[1].slot, "slot_melee")
        H.equal(plan.actions[1].backend_id, "ID_M")
        H.equal(plan.actions[1].route, Core.ROUTE_INVENTORY)
        H.equal(plan.actions[2].slot, "slot_hat")
        H.equal(plan.actions[2].route, Core.ROUTE_ATTACHMENT)
        H.equal(plan.actions[3].slot, "slot_necklace")
        H.equal(plan.skipped_same, 1)     -- ranged
        H.equal(plan.skipped_empty, 2)    -- ring, trinket (nothing desired)

        -- A live state identical to desired plans zero work (idempotent re-run).
        local clean = Core.plan(desired, keys,
            { slot_melee = "ID_M", slot_ranged = "ID_R", slot_hat = "ID_H", slot_necklace = "ID_N" }, {})
        H.equal(#clean.actions, 0)
        H.equal(clean.skipped_same, 4)
    end)

    H.test("issue 1033 plan is non-destructive for unresolvable or empty desired ids", function()
        -- Unresolvable desired id (no masterlist key) is a SKIP, never an equip
        -- (issues #375/#387 non-destructive doctrine).
        local plan = Core.plan({ slot_melee = "LATE_UUID" }, {}, { slot_melee = "OLD" }, {})
        H.equal(#plan.actions, 0)
        H.equal(plan.skipped_unresolvable, 1)
        -- Nothing desired anywhere plans nothing (deliberately-empty jewelry stays empty).
        local empty = Core.plan({}, {}, { slot_ring = "LIVE_RING" }, {})
        H.equal(#empty.actions, 0)
        H.equal(empty.skipped_empty, 6)
    end)

    H.test("issue 1033 plan matches by item key when the live backend id is unstamped", function()
        -- Spawn paths may not stamp item_data.backend_id; a matching item key means
        -- the slot is already presented (no churn), a differing key re-equips.
        local desired = { slot_melee = "ID_M" }
        local keys = { slot_melee = "k_same" }
        local same = Core.plan(desired, keys, {}, { slot_melee = "k_same" })
        H.equal(#same.actions, 0)
        H.equal(same.skipped_same, 1)
        local diff = Core.plan(desired, keys, {}, { slot_melee = "k_other" })
        H.equal(#diff.actions, 1)
        -- Differing ids re-equip even when the key matches: the reset may restore an
        -- official instance with different properties/traits.
        local props = Core.plan(desired, keys, { slot_melee = "OTHER_ID" }, { slot_melee = "k_same" })
        H.equal(#props.actions, 1)
    end)
end
