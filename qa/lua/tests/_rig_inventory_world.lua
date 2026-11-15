-- _rig_inventory_world.lua: the stub career, loadout and backend world of the inventory helper tests (WP-H-06).
--
-- Shared by test_rig_api_inventory.lua and test_rig_api_wire.lua; not a suite. Load it with
--   local inventory_world = assert(loadfile(repo_root .. "/qa/lua/tests/_rig_inventory_world.lua"))()
-- and call inventory_world(env) on a booted simulated game (_rig_driver_env.lua) before running it. request_profile
-- respawns the hero as the new career three player reads later; BackendUtils keeps loadouts in row 1 of a stub
-- backend mirror with an acknowledged copy (read by qa/runtime/_shared/official_mirror.lua); the inventory,
-- attachment and cosmetic systems record what they were asked to show. w.on_equip(unit, slot_name, backend_id), when
-- set, runs inside create_equipment_in_slot.
return function(env)
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
                if w.on_equip then
                    w.on_equip(unit, slot_name, backend_id)
                end
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
