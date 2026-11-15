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

    local function inventory_world(env)
        local w = {
            profile = "empire_soldier",
            career = "es_mercenary",
            unit = { name = "hero 1" },
            spawned = 1,
            requests = {},
            shown = {},
            events = 0,
            in_coroutine = {},
            held = {},
        }
        local melee = { slot_type = "melee", can_wield = { "es_mercenary", "es_huntsman" } }
        local items = {
            id_sword = { backend_id = "id_sword", key = "es_1h_sword", data = melee },
            id_sword2 = { backend_id = "id_sword2", key = "es_2h_sword", data = melee },
            id_gun = { backend_id = "id_gun", key = "es_handgun", data = { slot_type = "ranged" } },
            id_hat = { backend_id = "id_hat", key = "hat_a", data = { slot_type = "hat" } },
            id_hat2 = { backend_id = "id_hat2", key = "hat_b", data = { slot_type = "hat" } },
            id_frame = { backend_id = "id_frame", key = "frame_a", data = { slot_type = "frame" } },
            id_frame2 = { backend_id = "id_frame2", key = "frame_b", data = { slot_type = "frame" } },
        }
        -- loadouts live in a stub backend mirror (row 1 of _career_data) with an acknowledged copy, so the shared
        -- official_mirror helper and the driver's write shield see the same rows the helpers change
        local function rows()
            return {
                es_mercenary = { { slot_melee = "id_sword", slot_ranged = "id_gun", slot_hat = "id_hat", slot_frame = "id_frame" } },
                es_huntsman = { { slot_melee = "id_sword" } },
            }
        end
        w.mirror = { _career_data = rows(), _career_data_mirror = rows(), _inventory_items = items, _unlocked_cosmetics = {
            hat_a = true, hat_b = true, frame_a = true, frame_b = true, id_hat = true, id_hat2 = true, id_frame = true, id_frame2 = true,
        } }
        w.loadouts = { es_mercenary = w.mirror._career_data.es_mercenary[1], es_huntsman = w.mirror._career_data.es_huntsman[1] }
        env.get_mod = function() return nil end
        local function note_call(name)
            if coroutine.running() then
                w.in_coroutine[#w.in_coroutine + 1] = name
            end
        end
        -- a requested career takes effect three player reads later, with a new hero unit
        local function tick()
            local pending = w.pending
            if pending then
                pending.reads = pending.reads - 1
                if pending.reads <= 0 then
                    w.pending = nil
                    w.profile, w.career = pending.profile, pending.career
                    w.spawned = w.spawned + 1
                    w.unit = { name = "hero " .. w.spawned }
                end
            end
        end
        env.Unit.alive = function(unit)
            return unit ~= nil and unit == w.unit
        end
        env.Managers.player.local_player = function()
            tick()
            return {
                player_unit = w.unit,
                career_name = function() return w.career end,
                profile_display_name = function() return w.profile end,
            }
        end
        env.Managers.state.network = {
            request_profile = function(_, local_player_id, profile, career, force_respawn)
                note_call("request_profile")
                w.requests[#w.requests + 1] = table.concat({ tostring(local_player_id), profile, career, tostring(force_respawn) }, " ")
                w.unit = nil
                w.pending = { profile = profile, career = career, reads = 3 }
            end,
        }
        env.Managers.state.entity = {
            system = function(_, name)
                return {
                    set_equipped_frame = function(_, unit, key)
                        note_call("set_equipped_frame")
                        w.shown[#w.shown + 1] = name .. " frame=" .. key .. " on " .. unit.name
                    end,
                }
            end,
        }
        env.Managers.state.event = {
            trigger = function(_, name)
                if name == "event_set_loadout_items" then
                    w.events = w.events + 1
                end
            end,
        }
        local items_interface = {
            get_item_from_id = function(_, id) return items[id] end,
            get_item_from_key = function(_, key)
                for _, item in pairs(items) do
                    if item.key == key then
                        return item
                    end
                end
            end,
            get_all_backend_items = function() return items end,
        }
        env.Managers.backend = {
            get_backend_mirror = function() return w.mirror end,
            get_interface = function(_, name)
                if name == "items" then
                    return items_interface
                elseif name == "hero_attributes" then
                    return { get = function(_, hero, attribute) return attribute == "experience" and 12345 or nil end }
                end
            end,
        }
        local function career(name, unlocked)
            return {
                name = name,
                is_unlocked_function = function(self, hero_name, level)
                    w.unlock_asked = self.name .. " " .. hero_name .. " " .. tostring(level)
                    return unlocked
                end,
            }
        end
        env.SPProfiles = {
            { display_name = "empire_soldier", careers = { career("es_mercenary", true), career("es_huntsman", true), career("es_questingknight", false) } },
        }
        env.FindProfileIndex = function(name)
            for index, profile in ipairs(env.SPProfiles) do
                if profile.display_name == name then
                    return index
                end
            end
        end
        env.ExperienceSettings = { get_level = function(experience) return experience == 12345 and 30 or 0 end }
        env.InventorySettings = {
            slots_by_name = {
                slot_melee = { name = "slot_melee", type = "melee", stored_in_backend = true },
                slot_ranged = { name = "slot_ranged", type = "ranged", stored_in_backend = true },
                slot_hat = { name = "slot_hat", type = "hat", stored_in_backend = true },
                slot_frame = { name = "slot_frame", type = "frame", stored_in_backend = true },
                slot_healthkit = { name = "slot_healthkit", type = "healthkit" },
            },
        }
        env.BackendUtils = {
            get_loadout_item_id = function(career_name, slot_name)
                return (w.loadouts[career_name] or {})[slot_name]
            end,
            set_loadout_item = function(backend_id, career_name, slot_name)
                note_call("set_loadout_item")
                w.loadouts[career_name] = w.loadouts[career_name] or {}
                w.loadouts[career_name][slot_name] = backend_id
            end,
        }
        local function extension(unit, system)
            return {
                create_equipment_in_slot = function(_, slot_name, backend_id)
                    note_call("create_equipment_in_slot")
                    w.shown[#w.shown + 1] = system .. " " .. slot_name .. "=" .. backend_id .. " on " .. unit.name
                    w.held[slot_name] = backend_id
                end,
                create_attachment_in_slot = function(_, slot_name, backend_id)
                    note_call("create_attachment_in_slot")
                    w.shown[#w.shown + 1] = system .. " " .. slot_name .. "=" .. backend_id .. " on " .. unit.name
                end,
                get_slot_data = function(_, slot_name)
                    return w.held[slot_name] and { item_data = { backend_id = w.held[slot_name] } }
                end,
            }
        end
        env.ScriptUnit = {
            extension = extension,
            has_extension = function(unit, system)
                return unit == w.unit and extension(unit, system) or nil
            end,
        }
        return w
    end

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
