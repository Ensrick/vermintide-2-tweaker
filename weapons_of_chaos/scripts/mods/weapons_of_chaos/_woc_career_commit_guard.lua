--[[
#402 / #1688 (WP-CIM-07): keep Weapons of Chaos relic ids out of
the career-data commit.

WOC relics exist only in the local mirror (MoreItemsLibrary rows such as
`woc_blightreaper_001`). An equipped one is written into the mirror's
_career_data (Vermintide-2-Source-Code/scripts/managers/backend_playfab/
backend_interface_item_playfab.lua:635-665, playfab_mirror_base.lua:1928-1941);
vanilla diffs that table against the server copy in _check_career_data
(playfab_mirror_base.lua:3409-3628, only caller :2885) and sends the result in
updateHeroAttributes. The official sign-in then finds an id the account does
not own and resets the slot to starting gear (:1579-1721).

The shared guard (_lib_official_loadout_guard) swaps every id WOC created for
the mirror's server value during the vanilla call, detaches the returned
loadouts, and restores the id so the item stays equipped for the session. The
predicate is the pure `_woc_wire_policy.is_woc_backend_id`. Exactly one hook,
on the concrete PlayFabMirrorAdventure class; VMF chains it with the other
mods' guards (cim, cwv) on the same method.
]]

return function(context)
    local mod = assert(context.mod, "career commit guard needs mod")
    local guard = assert(context.guard, "career commit guard needs the shared guard")
    local is_owned = assert(context.is_owned_id, "career commit guard needs the id predicate")
    local rt_register = assert(context.rt_register, "career commit guard needs rt_register")
    local print_line = context.print_line or function() end

    local REPORT_LIMIT = 12
    local reports_printed = 0
    local function report(scrubbed, unsafe)
        mod._woc402_last_report = { scrubbed = scrubbed, unsafe = unsafe }
        if reports_printed < REPORT_LIMIT then
            reports_printed = reports_printed + 1
            pcall(print_line, "[woc:402] scrubbed=%d unsafe=%d", scrubbed, unsafe)
        end
    end

    mod:hook("PlayFabMirrorAdventure", "_check_career_data", function(func, self, careers_data, career_data_mirror)
        return guard.wrap(func, self, careers_data, career_data_mirror, is_owned, report)
    end)
    mod._woc402_guard_installed = true
    mod._woc402_is_owned_id = is_owned

    rt_register("issue402_career_commit_guard", function()
        if not mod._woc402_guard_installed then
            return "career commit guard was not installed"
        end
        local owned = "woc_blightreaper_001"
        if is_owned(owned) ~= true then
            return "the WOC id predicate rejects a WOC relic id"
        end
        if is_owned("A1B2C3D4E5F60708") then
            return "the WOC id predicate accepts an account instance id"
        end
        local careers_data = {
            rt_career = {
                { slot_melee = "woc402-rt-official-1" },
                { slot_melee = owned },
            },
        }
        local career_data_mirror = {
            rt_career = {
                { slot_melee = "woc402-rt-official-1" },
                { slot_melee = "woc402-rt-official-2" },
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
            careers_data, career_data_mirror, is_owned, function() end)
        if not ok then
            return "guard.wrap raised: " .. tostring(dirty)
        end
        local hero = type(dirty_hero_data) == "table" and dirty_hero_data.rt_hero
        local career = hero and hero.careers and hero.careers.rt_career
        local sent = career and career.loadouts and career.loadouts["2"]
        if type(sent) ~= "table" then
            return "the fixture commit lost its dirty loadout"
        end
        if sent.slot_melee ~= "woc402-rt-official-2" then
            return "the payload did not carry the server value: " .. tostring(sent.slot_melee)
        end
        if careers_data.rt_career[2].slot_melee ~= owned then
            return "the WOC id was not restored to the fixture"
        end
        return nil
    end)
end
