-- test_rig_api_inventory.lua: offline tests of the rig's helper group lib/inventory.lua (T.career, T.equip,
-- T.loadout, T.backend_items), WP-H-06 group "inventory and career".
--
-- Boots the real bootstrap and driver with the real group in plan.libs inside the simulated game of
-- _rig_driver_env.lua, plus a stub world for the calls the group makes: request_profile respawns the hero as the
-- new career a few reads later; BackendUtils keeps loadouts per career; the inventory, attachment and cosmetic
-- systems record what they were asked to show. This proves the helpers' control flow, restores and evidence lines
-- only, never that the game reacts the same way: that is what qa/runtime/plans/api-selftest.json is for.
return function(H, repo_root)
    local E = assert(loadfile(repo_root .. "/qa/lua/tests/_rig_driver_env.lua"))()(H, repo_root)
    local tag, first = E.tag, E.first

    local inventory_world = assert(loadfile(repo_root .. "/qa/lua/tests/_rig_inventory_world.lua"))()

    local function run(cases)
        local plan = E.make_plan(cases, { libs = { E.lib_entry("inventory") } })
        local object, env, lines = E.boot(plan)
        local w = inventory_world(env)
        H.truthy(E.run_to_end(object, env), "run completed")
        return lines, w
    end

    H.test("rig T.career: the game's request_profile in the main update, waits for the respawn, restores at the end", function()
        local lines, w = run({
            { id = "switch", src = [[
return { run = function(T)
    local unit = T.career("empire_soldier", "es_huntsman")
    T.expect(unit ~= nil, "T.career returns the new hero unit")
    T.expect_eq(T.local_player():career_name(), "es_huntsman", "the player reports the new career")
    local same = T.career("empire_soldier", "es_huntsman")
    T.expect(same == unit, "asking for the career already played returns the hero without a request")
end }
]] },
            { id = "after", src = [[
return { run = function(T)
    local back = T.wait_until(function() return T.local_player():career_name() == "es_mercenary" end, 5, "career restored")
    T.expect(back, "the career before the first T.career is requested again at cleanup")
end }
]] },
        })
        H.truthy(first(lines, tag .. "CASE END id=switch verdict=PASS asserts=3 failed=0"), "switch passes")
        H.truthy(first(lines, tag .. "CASE END id=after verdict=PASS"), "the next case sees the old career again")
        H.equal(#w.requests, 2, "one request to switch, one to restore")
        H.equal(w.requests[1], "1 empire_soldier es_huntsman true", "request_profile(1, profile, career, true) as the game's test hook calls it")
        H.equal(w.requests[2], "1 empire_soldier es_mercenary true", "the restore requests the old career")
        H.equal(w.unlock_asked, "es_huntsman empire_soldier 30", "unlock asked with the hero level from its experience")
        H.truthy(first(lines, tag .. "CAREER id=switch from=es_mercenary to=es_huntsman seconds="), "CAREER line")
        H.truthy(first(lines, tag .. "CAREER RESTORE id=switch career=es_mercenary"), "CAREER RESTORE line")
        H.equal(table.concat(w.in_coroutine, ","), "", "no setter ran inside the case coroutine")
    end)

    H.test("rig T.career: a locked or unknown career is INCONCLUSIVE and requests nothing", function()
        local lines, w = run({
            { id = "locked", src = "return { run = function(T) T.career('empire_soldier', 'es_questingknight') end }" },
            { id = "unknown", src = "return { run = function(T) T.career('empire_soldier', 'wh_captain') end }" },
            { id = "no-profile", src = "return { run = function(T) T.career('nobody', 'x') end }" },
        })
        H.truthy(first(lines, tag .. "CASE END id=locked verdict=INCONCLUSIVE .*career es_questingknight unlocked for this account"), "locked career")
        H.truthy(first(lines, tag .. "CASE END id=unknown verdict=INCONCLUSIVE .*career wh_captain belongs to empire_soldier"), "career of another hero")
        H.truthy(first(lines, tag .. "CASE END id=no%-profile verdict=INCONCLUSIVE .*profile nobody exists"), "unknown profile")
        H.equal(#w.requests, 0, "no profile request")
    end)

    H.test("rig T.equip: the game's setter, shown on the hero like the hero view does, restored at the end", function()
        local lines, w = run({
            { id = "equip", src = [[
return { run = function(T)
    T.expect_eq(T.equip(nil, "slot_melee", "es_2h_sword"), "id_sword2", "equip by item key returns the backend id")
    T.expect_eq(T.equip("es_mercenary", "slot_hat", "id_hat2"), "id_hat2", "equip by backend id")
    T.equip(nil, "slot_frame", "frame_b")
    T.equip("es_huntsman", "slot_melee", "id_sword2")
    T.expect_eq(T.equip(nil, "slot_melee", "id_sword"), "id_sword", "a second change of the same slot")
    local loadout = T.loadout()
    T.expect_eq(loadout.slot_hat, "id_hat2", "T.loadout reads the current loadout")
    T.expect_eq(loadout.slot_healthkit, nil, "T.loadout lists loadout slots only")
    T.expect_eq(#T.backend_items(function(item) return item.key:find("^hat_") ~= nil end), 2, "T.backend_items filters")
end }
]] },
        })
        H.truthy(first(lines, tag .. "CASE END id=equip verdict=PASS asserts=6 failed=0"), "equip passes")
        H.equal(w.loadouts.es_mercenary.slot_melee, "id_sword", "melee back to the first item")
        H.equal(w.loadouts.es_mercenary.slot_hat, "id_hat", "hat restored")
        H.equal(w.loadouts.es_mercenary.slot_frame, "id_frame", "frame restored")
        H.equal(w.loadouts.es_huntsman.slot_melee, "id_sword", "the other career's loadout restored, not shown")
        H.equal(w.shown[1], "inventory_system slot_melee=id_sword2 on hero 1", "a weapon is re-created in its slot")
        H.equal(w.shown[2], "attachment_system slot_hat=id_hat2 on hero 1", "a hat is an attachment")
        H.equal(w.shown[3], "cosmetic_system frame=frame_b on hero 1", "a frame goes to the cosmetic system")
        H.equal(w.shown[4], "inventory_system slot_melee=id_sword on hero 1", "the other career's change is not shown: next is the second melee change")
        H.equal(#w.shown, 7, "four shown during the case, three restores shown at cleanup")
        H.equal(w.events, 7, "event_set_loadout_items after every shown change")
        H.truthy(first(lines, tag .. "EQUIP id=equip career=es_mercenary slot=slot_melee item=id_sword2 key=es_2h_sword was=id_sword"), "EQUIP line")
        H.truthy(first(lines, tag .. "EQUIP RESTORE id=equip career=es_huntsman slot=slot_melee item=id_sword"), "restore line of the other career")
        H.truthy(first(lines, tag .. "CLEANUP id=equip actions=4 errors=0"), "one restore per career and slot")
        H.equal(table.concat(w.in_coroutine, ","), "", "no setter ran inside the case coroutine")
    end)

    -- The inventory and career cases of qa/runtime/plans/api-selftest.json, in its order, against the stub world:
    -- catches a script defect before the plan costs a rig run. A PASS here says nothing about the game.
    H.test("rig api-selftest cases: inventory, restore and career pass in the simulated game", function()
        local function case(id, file)
            return { id = id, src = E.read(repo_root .. "/qa/runtime/_rig/" .. file) }
        end
        local plan = E.make_plan({
            case("api-inventory", "api_inventory.lua"),
            case("api-inventory-restored", "api_inventory_restored.lua"),
            case("api-career", "api_career.lua"),
        }, {
            libs = { E.lib_entry("inventory") },
            shared = { { id = "official_mirror", hex = E.hex(E.read(repo_root .. "/qa/runtime/_shared/official_mirror.lua")) } },
        })
        local object, env, lines = E.boot(plan)
        local w = inventory_world(env)
        H.truthy(E.run_to_end(object, env), "run completed")
        for _, id in ipairs({ "api%-inventory", "api%-inventory%-restored", "api%-career" }) do
            H.truthy(first(lines, tag .. "CASE END id=" .. id .. " verdict=PASS"), id .. " passes: " .. tostring(first(lines, tag .. "CASE END id=" .. id)))
        end
        H.truthy(first(lines, tag .. "EQUIP RESTORE id=api%-inventory career=es_mercenary slot=slot_melee item=id_sword"), "the plan's host_expect_log restore line is printed")
        H.equal(w.loadouts.es_mercenary.slot_melee, "id_sword", "melee item back")
        H.equal(w.career, "es_mercenary", "career back")
        H.equal(#w.requests, 2, "two career requests: there and back")
    end)

    H.test("rig T.equip: unknown slot or item is INCONCLUSIVE; an ERROR still restores", function()
        local lines, w = run({
            { id = "bad-slot", src = "return { run = function(T) T.equip(nil, 'slot_healthkit', 'id_sword') end }" },
            { id = "not-owned", src = "return { run = function(T) T.equip(nil, 'slot_melee', 'we_longbow') end }" },
            { id = "boom", src = "return { run = function(T) T.equip(nil, 'slot_ranged', 'id_sword2') error('planted error after T.equip') end }" },
        })
        H.truthy(first(lines, tag .. "CASE END id=bad%-slot verdict=INCONCLUSIVE .*slot slot_healthkit is a loadout slot"), "not a loadout slot")
        H.truthy(first(lines, tag .. "CASE END id=not%-owned verdict=INCONCLUSIVE .*item we_longbow owned"), "item not owned")
        H.truthy(first(lines, tag .. "CASE END id=boom verdict=ERROR .*planted error after T.equip"), "ERROR reported")
        H.equal(w.loadouts.es_mercenary.slot_ranged, "id_gun", "restored after the ERROR")
    end)
end
