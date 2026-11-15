--[[
#402 / #1688 (WP-CIM-01): keep Crafting in Modded backend ids out of the
career-data commit.

A craft auto-equips through items:set_loadout_item, which writes the crafted id
into the mirror's _career_data (Vermintide-2-Source-Code/scripts/managers/
backend_playfab/backend_interface_item_playfab.lua:635-665,
playfab_mirror_base.lua:1928-1941). At commit, vanilla diffs that table against
the server copy in _check_career_data (playfab_mirror_base.lua:3409-3628, only
caller :2885) and sends the result in updateHeroAttributes. The official
sign-in then finds an id that is not in the inventory and resets the slot to
starting gear (:1579-1721).

The shared guard (_lib_official_loadout_guard) swaps every id this mod owns for
the mirror's server value during the vanilla call, detaches the returned
loadouts, and restores the id so the craft stays equipped for the session.
Exactly one hook: the concrete PlayFabMirrorAdventure class (class() copies
parent methods at definition time).
]]

return function(context)
    local mod = assert(context.mod, "career commit guard needs mod")
    local guard = assert(context.guard, "career commit guard needs the shared guard")
    local rt_register = assert(context.rt_register, "career commit guard needs rt_register")
    local print_line = context.print_line or function() end

    local REPORT_LIMIT = 12
    local reports_printed = 0
    local function report(scrubbed, unsafe)
        mod._cim402_last_report = { scrubbed = scrubbed, unsafe = unsafe }
        if reports_printed < REPORT_LIMIT then
            reports_printed = reports_printed + 1
            print_line("[cim:402] scrubbed=%d unsafe=%d", scrubbed, unsafe)
        end
    end

    mod:hook("PlayFabMirrorAdventure", "_check_career_data", function(func, self, careers_data, career_data_mirror)
        return guard.wrap(func, self, careers_data, career_data_mirror, mod._cim_is_modded_backend_id, report)
    end)
    mod._cim402_guard_installed = true

    rt_register("issue402_career_commit_guard", function()
        if not mod._cim402_guard_installed then
            return "career commit guard was not installed"
        end
        local owned = "cim402-rt-owned-id"
        local careers_data = {
            rt_career = {
                { slot_melee = "cim402-rt-official-1" },
                { slot_melee = owned },
            },
        }
        local career_data_mirror = {
            rt_career = {
                { slot_melee = "cim402-rt-official-1" },
                { slot_melee = "cim402-rt-official-2" },
            },
        }
        -- Shape of vanilla's dirty_hero_data: the loadout entry is a reference
        -- to the live careers_data table (playfab_mirror_base.lua:3523, :3541).
        local function fake_check(_, data)
            return true, nil, {
                rt_hero = {
                    careers = {
                        rt_career = {
                            loadouts = { ["2"] = data.rt_career[2] },
                            deleted_loadouts = {},
                        },
                    },
                },
            }
        end
        local ok, dirty, _, dirty_hero_data = pcall(guard.wrap, fake_check, nil,
            careers_data, career_data_mirror,
            function(value) return value == owned end,
            function() end)
        if not ok then
            return "guard.wrap raised: " .. tostring(dirty)
        end
        local hero = type(dirty_hero_data) == "table" and dirty_hero_data.rt_hero
        local career = hero and hero.careers and hero.careers.rt_career
        local sent = career and career.loadouts and career.loadouts["2"]
        if type(sent) ~= "table" then
            return "the fixture commit lost its dirty loadout"
        end
        if sent.slot_melee == owned then
            return "the owned id reached the commit payload"
        end
        if sent.slot_melee ~= "cim402-rt-official-2" then
            return "the payload did not carry the server value: " .. tostring(sent.slot_melee)
        end
        if careers_data.rt_career[2].slot_melee ~= owned then
            return "the owned id was not restored to the fixture"
        end
        return nil
    end)
end
