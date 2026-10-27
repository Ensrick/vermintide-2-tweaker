-- ============================================================
-- Loadout Save/Restore (v0.1)
-- ============================================================
-- Clean reimplementation of loadout_manager_vt2's save/restore. The legacy
-- mod OR-merged gear and cosmetics into a single backend_id-per-slot lookup
-- and iterated `slots_by_slot_index`, which routed weapon-skin items
-- (slot_type=melee) into gear slots like slot_ranged and triggered the
-- engine's "cannot equip item in this slot type" rejection. We keep the
-- two namespaces strictly separated: gear iterates `slots_by_ui_slot_index`,
-- cosmetics iterate `slots_by_cosmetic_index`, and each item is validated
-- against its OWN target slot before any write.

local LOADOUT_SLOTS = 30

-- Local player + resolved career name. Returns (career_name, profile, career)
-- or (nil, reason) when no local player/profile is available.
local function _get_current_career()
    local pm = Managers.player
    if not pm then return nil, "Managers.player not available (not in a level?)" end
    local player = pm:local_player(1)
    if not player then return nil, "no local player" end
    local ok_pi, profile_index = pcall(player.profile_index, player)
    local ok_ci, career_index = pcall(player.career_index, player)
    if not (ok_pi and ok_ci and profile_index and career_index) then
        return nil, "could not read profile/career index"
    end
    local profile = SPProfiles and SPProfiles[profile_index]
    if not profile then return nil, "no profile for index " .. tostring(profile_index) end
    local career = profile.careers and profile.careers[career_index]
    if not career then return nil, "no career for index " .. tostring(career_index) end
    return career.name, profile, career
end

-- Localized career display name with safe fallback.
local function _career_display_name(career)
    if not career then return "?" end
    local key = career.display_name or career.name
    if not key then return "?" end
    local ok, name = pcall(Localize, key)
    return (ok and name) or key
end

-- Validate item slot-type compatibility before equipping. Vanilla's backend
-- reads the live CareerSettings item_slot_types_by_slot_name map for this exact
-- decision (playfab_mirror_base.lua:1662-1713, 3387-3402). Reading it on every
-- restore lets Career Tweaker add/remove Foot Knight secondary melee at runtime
-- without a GUT mod-identity dependency, cached clone, or hardcoded career list.
local _gut_loadout_slot_policy = mod:dofile(
    "scripts/mods/gui_tweaker_dev/_gut_loadout_slot_policy"
)

local function _validate_item_for_slot(item, slot_name, career_name)
    if type(_gut_loadout_slot_policy) ~= "table" or
       type(_gut_loadout_slot_policy.validate) ~= "function" then
        return false, "live career slot capability policy unavailable"
    end

    return _gut_loadout_slot_policy.validate(
        item and item.data,
        slot_name,
        career_name,
        CareerSettings
    )
end

if type(printf) == "function" then
    printf("[gut:619] saved-loadout validator=live_career_slot_capability")
end

_rt_register("issue619_saved_loadout_live_slot_capability", function()
    if type(_gut_loadout_slot_policy) ~= "table" or
       type(_gut_loadout_slot_policy.validate) ~= "function" then
        return "loadout slot capability policy unavailable"
    end

    local career_settings = {
        es_knight = {
            item_slot_types_by_slot_name = {
                slot_melee = { "melee" },
                slot_ranged = { "ranged" },
            },
        },
    }
    local item_data = { slot_type = "melee", can_wield = { "es_knight" } }
    local ok = _gut_loadout_slot_policy.validate(
        item_data, "slot_ranged", "es_knight", career_settings
    )
    if ok then return "Foot Knight melee accepted without live slot capability" end

    table.insert(career_settings.es_knight.item_slot_types_by_slot_name.slot_ranged, 1, "melee")
    ok = _gut_loadout_slot_policy.validate(
        item_data, "slot_ranged", "es_knight", career_settings
    )
    if not ok then return "Foot Knight melee rejected after live slot capability insertion" end

    table.remove(career_settings.es_knight.item_slot_types_by_slot_name.slot_ranged, 1)
    ok = _gut_loadout_slot_policy.validate(
        item_data, "slot_ranged", "es_knight", career_settings
    )
    if ok then return "Foot Knight melee remained accepted after live slot capability removal" end
end)

-- Snapshot the current loadout for `career_name`. Reads gear from
-- slots_by_ui_slot_index, cosmetics from slots_by_cosmetic_index, and
-- talents from the talents interface (cloned).
local function _snapshot_loadout(career_name)
    local items_iface = Managers.backend and Managers.backend:get_interface("items")
    if not items_iface then return nil, "no items interface" end
    local gear, cosmetics = {}, {}
    local frame_id = nil
    if InventorySettings and InventorySettings.slots_by_ui_slot_index then
        for _, slot in pairs(InventorySettings.slots_by_ui_slot_index) do
            local ok, id = pcall(items_iface.get_loadout_item_id, items_iface, career_name, slot.name)
            if ok and id then gear[slot.name] = id end
        end
    end
    if InventorySettings and InventorySettings.slots_by_cosmetic_index then
        for _, slot in pairs(InventorySettings.slots_by_cosmetic_index) do
            local ok, id = pcall(items_iface.get_loadout_item_id, items_iface, career_name, slot.name)
            if ok and id then
                cosmetics[slot.name] = id
                if slot.name == "slot_frame" then frame_id = id end
            end
        end
    end
    local talents = nil
    local talents_iface = Managers.backend and Managers.backend:get_interface("talents")
    if talents_iface then
        local ok, t = pcall(talents_iface.get_talents, talents_iface, career_name)
        if ok and type(t) == "table" then talents = table.clone(t) end
    end
    return {
        saved_at    = os.time(),
        career_name = career_name,
        frame       = frame_id,
        gear        = gear,
        cosmetics   = cosmetics,
        talents     = talents or {},
    }
end

-- Apply a saved loadout. Cross-career restore is out of scope for v0.1 — we
-- reject if the snapshot's career doesn't match the current one. Returns
-- (gear_count, cosmetic_count, talents_applied_bool, error_count).
local function _apply_loadout(loadout, current_career_name)
    if not loadout then return 0, 0, false, 0 end
    if loadout.career_name and loadout.career_name ~= current_career_name then
        mod:echo(string.format("Loadout was saved for %s; switch to that career first (cross-career restore is not supported in v0.1).",
            tostring(loadout.career_name)))
        return 0, 0, false, 1
    end
    local items_iface = Managers.backend and Managers.backend:get_interface("items")
    if not items_iface then
        mod:echo("No items interface; cannot restore loadout.")
        return 0, 0, false, 1
    end
    local gear_count, cos_count, errors = 0, 0, 0

    -- Gear namespace -> slots_by_ui_slot_index only.
    if loadout.gear and InventorySettings and InventorySettings.slots_by_ui_slot_index then
        local gear_slot_names = {}
        for _, slot in pairs(InventorySettings.slots_by_ui_slot_index) do
            gear_slot_names[slot.name] = true
        end
        for slot_name, backend_id in pairs(loadout.gear) do
            if not gear_slot_names[slot_name] then
                mod:echo(string.format("Skipping gear slot %s -- not a known gear slot.", tostring(slot_name)))
                -- _dbg: loadout_apply_skip
                pcall(_dbg_alert, "[gui_tweaker] loadout_apply_skip: slot_name=%s reason=not_a_gear_slot",
                    tostring(slot_name))
                errors = errors + 1
            else
                local ok_item, item = pcall(items_iface.get_item_from_id, items_iface, backend_id)
                if not (ok_item and item) then
                    mod:echo(string.format("Skipping %s -- item %s no longer in backend.", slot_name, tostring(backend_id)))
                    pcall(_dbg_alert, "[gui_tweaker] loadout_apply_skip: slot_name=%s reason=item_not_in_backend",
                        tostring(slot_name))
                    errors = errors + 1
                else
                    local valid, reason = _validate_item_for_slot(item, slot_name, current_career_name)
                    if not valid then
                        mod:echo(string.format("Skipping %s -- %s.", slot_name, tostring(reason)))
                        pcall(_dbg_alert, "[gui_tweaker] loadout_apply_skip: slot_name=%s reason=%s",
                            tostring(slot_name), tostring(reason))
                        errors = errors + 1
                    else
                        local generation_before = mod._gut925_generation()
                        local ok_set, err = pcall(BackendUtils.set_loadout_item, backend_id, current_career_name, slot_name)
                        if ok_set then
                            mod._gut925_publish_if_unobserved(generation_before,
                                current_career_name, slot_name, backend_id, item)
                            gear_count = gear_count + 1
                            -- _dbg: loadout_apply_item
                            pcall(_dbg, "[gui_tweaker] loadout_apply_item: slot_name=%s item=%s",
                                tostring(slot_name), tostring(backend_id))
                        else
                            mod:echo(string.format("Skipping %s -- set_loadout_item failed: %s", slot_name, tostring(err)))
                            pcall(_dbg_alert, "[gui_tweaker] loadout_apply_skip: slot_name=%s reason=set_loadout_item_failed:%s",
                                tostring(slot_name), tostring(err))
                            errors = errors + 1
                        end
                    end
                end
            end
        end
    end

    -- Cosmetic namespace -> slots_by_cosmetic_index only.
    if loadout.cosmetics and InventorySettings and InventorySettings.slots_by_cosmetic_index then
        local cos_slot_names = {}
        for _, slot in pairs(InventorySettings.slots_by_cosmetic_index) do
            cos_slot_names[slot.name] = true
        end
        for slot_name, backend_id in pairs(loadout.cosmetics) do
            if not cos_slot_names[slot_name] then
                mod:echo(string.format("Skipping cosmetic slot %s -- not a known cosmetic slot.", tostring(slot_name)))
                pcall(_dbg_alert, "[gui_tweaker] loadout_apply_skip: slot_name=%s reason=not_a_cosmetic_slot",
                    tostring(slot_name))
                errors = errors + 1
            else
                local ok_item, item = pcall(items_iface.get_item_from_id, items_iface, backend_id)
                if not (ok_item and item) then
                    mod:echo(string.format("Skipping %s -- item %s no longer in backend.", slot_name, tostring(backend_id)))
                    pcall(_dbg_alert, "[gui_tweaker] loadout_apply_skip: slot_name=%s reason=item_not_in_backend",
                        tostring(slot_name))
                    errors = errors + 1
                else
                    local valid, reason = _validate_item_for_slot(item, slot_name, current_career_name)
                    if not valid then
                        mod:echo(string.format("Skipping %s -- %s.", slot_name, tostring(reason)))
                        pcall(_dbg_alert, "[gui_tweaker] loadout_apply_skip: slot_name=%s reason=%s",
                            tostring(slot_name), tostring(reason))
                        errors = errors + 1
                    else
                        local generation_before = mod._gut925_generation()
                        local ok_set, err = pcall(BackendUtils.set_loadout_item, backend_id, current_career_name, slot_name)
                        if ok_set then
                            mod._gut925_publish_if_unobserved(generation_before,
                                current_career_name, slot_name, backend_id, item)
                            cos_count = cos_count + 1
                            pcall(_dbg, "[gui_tweaker] loadout_apply_item: slot_name=%s item=%s",
                                tostring(slot_name), tostring(backend_id))
                        else
                            mod:echo(string.format("Skipping %s -- set_loadout_item failed: %s", slot_name, tostring(err)))
                            pcall(_dbg_alert, "[gui_tweaker] loadout_apply_skip: slot_name=%s reason=set_loadout_item_failed:%s",
                                tostring(slot_name), tostring(err))
                            errors = errors + 1
                        end
                    end
                end
            end
        end
    end

    -- Talents.
    local talents_applied = false
    if loadout.talents and #loadout.talents > 0 then
        local talents_iface = Managers.backend and Managers.backend:get_interface("talents")
        if talents_iface then
            local ok_t, err_t = pcall(talents_iface.set_talents, talents_iface, current_career_name, loadout.talents)
            if ok_t then
                talents_applied = true
            else
                mod:echo("Talent restore failed: " .. tostring(err_t))
                errors = errors + 1
            end
        end
    end

    return gear_count, cos_count, talents_applied, errors
end

local function _get_all_loadouts()
    return mod:get("loadouts") or {}
end

local function _save_loadout_to_slot(career_name, n, loadout)
    local all = _get_all_loadouts()
    all[career_name] = all[career_name] or {}
    all[career_name][n] = loadout
    mod:set("loadouts", all)
end

local function _load_loadout_from_slot(career_name, n)
    local all = _get_all_loadouts()
    local by_career = all[career_name]
    return by_career and by_career[n] or nil
end

-- Parse + range-check the slot index argument. Returns (n, nil) or (nil, reason).
local function _parse_slot_arg(arg)
    local n = tonumber(arg)
    if not n then return nil, "slot must be a number 1-" .. LOADOUT_SLOTS end
    n = math.floor(n)
    if n < 1 or n > LOADOUT_SLOTS then return nil, "slot must be 1-" .. LOADOUT_SLOTS end
    return n
end

mod:command("save_loadout", "Save current loadout to slot N (1-30)", function(arg)
    local n, reason = _parse_slot_arg(arg)
    if not n then mod:echo("Save failed: " .. reason) return end
    local career_name, profile_or_err, career = _get_current_career()
    if not career_name then mod:echo("Save failed: " .. tostring(profile_or_err)) return end
    local loadout, snap_err = _snapshot_loadout(career_name)
    if not loadout then mod:echo("Save failed: " .. tostring(snap_err)) return end
    _save_loadout_to_slot(career_name, n, loadout)
    local gear_n, cos_n = 0, 0
    for _ in pairs(loadout.gear) do gear_n = gear_n + 1 end
    for _ in pairs(loadout.cosmetics) do cos_n = cos_n + 1 end
    local talents_n = #(loadout.talents or {})
    mod:echo(string.format("Saved loadout to slot %d for career %s (%d gear, %d cosmetics, %d talents)",
        n, _career_display_name(career), gear_n, cos_n, talents_n))
    -- _dbg: loadout_save
    pcall(function()
        _dbg("[gui_tweaker] loadout_save: slot=%d career=%s gear=%d cosmetics=%d talents=%d",
            n, tostring(career_name), gear_n, cos_n, talents_n)
        for slot_name, backend_id in pairs(loadout.gear) do
            _dbg("[gui_tweaker]   gear.%s = %s", tostring(slot_name), tostring(backend_id))
        end
        for slot_name, backend_id in pairs(loadout.cosmetics) do
            _dbg("[gui_tweaker]   cosmetics.%s = %s", tostring(slot_name), tostring(backend_id))
        end
        local talent_strs = {}
        for i = 1, #(loadout.talents or {}) do talent_strs[i] = tostring(loadout.talents[i]) end
        _dbg("[gui_tweaker]   talents = %s", table.concat(talent_strs, ","))
    end)
end)

mod:command("load_loadout", "Load loadout from slot N (1-30) for current career", function(arg)
    local n, reason = _parse_slot_arg(arg)
    if not n then mod:echo("Load failed: " .. reason) return end
    local career_name, profile_or_err, career = _get_current_career()
    if not career_name then mod:echo("Load failed: " .. tostring(profile_or_err)) return end
    local loadout = _load_loadout_from_slot(career_name, n)
    if not loadout then
        mod:echo(string.format("No loadout in slot %d for career %s", n, _career_display_name(career)))
        return
    end
    local gear_n, cos_n, talents_ok, err_n = _apply_loadout(loadout, career_name)
    mod:echo(string.format("Loaded slot %d for %s -- applied %d gear, %d cosmetics, talents %s, %d errors",
        n, _career_display_name(career), gear_n, cos_n, talents_ok and "yes" or "no", err_n))
    -- _dbg: loadout_apply
    pcall(_dbg, "[gui_tweaker] loadout_apply: slot=%d career=%s gear_applied=%d cosmetics_applied=%d talents_set=%s errors=%d",
        n, tostring(career_name), gear_n, cos_n, talents_ok and "yes" or "no", err_n)
end)

mod:command("list_loadouts", "List saved loadouts for current career", function()
    local career_name, profile_or_err, career = _get_current_career()
    if not career_name then mod:echo("List failed: " .. tostring(profile_or_err)) return end
    local all = _get_all_loadouts()
    local by_career = all[career_name]
    if not by_career then
        mod:echo(string.format("No loadouts saved for %s", _career_display_name(career)))
        return
    end
    local printed = 0
    for n = 1, LOADOUT_SLOTS do
        local lo = by_career[n]
        if lo then
            local gear_n, cos_n = 0, 0
            for _ in pairs(lo.gear or {}) do gear_n = gear_n + 1 end
            for _ in pairs(lo.cosmetics or {}) do cos_n = cos_n + 1 end
            local ts = lo.saved_at and os.date("%Y-%m-%d %H:%M", lo.saved_at) or "?"
            mod:echo(string.format("[%d] saved %s -- %d gear, %d cosmetics", n, ts, gear_n, cos_n))
            printed = printed + 1
        end
    end
    if printed == 0 then
        mod:echo(string.format("No loadouts saved for %s", _career_display_name(career)))
    end
end)
