-- _cos_runtime_checks_persistence.lua -- Lazy LA persistence regression checks.
--
-- Registers the historical offhand, cosmetic, and cold-load checks using the
-- exact instances captured by the parent registrar. Installation only registers
-- closures: it never saves, reloads, restores, or inspects live runtime state.
--
-- Owned by: cosmetics_tweaker.lua. Consumed through private dependency injection
-- into _cos_runtime_checks.lua at the original three-check registration slot.
local M = {}

function M.install(mod, rt_register, deps)
    local _rt_register = rt_register
    local LA_PERSIST = deps.la_persist
    local ACTIVE_SKIN = deps.active_skin
    local OFFHAND_SELECTION = deps.offhand_selection

_rt_register("cos_la_offhand_persistence_roundtrip", function()
    if not (LA_PERSIST and LA_PERSIST.save_offhand
            and LA_PERSIST.commit_offhand_entry) then return "offhand API missing" end
    local bid, hand = "rt_fake_bid_0001", "left_hand_unit"
    LA_PERSIST.save_offhand(bid, hand, "rt_key", "rt_vanilla")
    local saved = LA_PERSIST.get_saved_offhands()
    local rec = saved and saved[bid] and saved[bid][hand]
    if not (rec and rec.armoury_key == "rt_key" and rec.vanilla_key == "rt_vanilla") then
        LA_PERSIST.clear_offhand(bid, hand)
        return "saved offhand did not read back"
    end
    LA_PERSIST.clear_offhand(bid, hand)
    saved = LA_PERSIST.get_saved_offhands()
    if saved and saved[bid] then return "cleared offhand still present" end

    local committed = LA_PERSIST.commit_offhand_entry({
        backend_id = bid,
        hand_field = hand,
        offhand_unit = "units/rt/dual_left",
        skin_key = "rt_dual_skin",
        player_unit = nil,
    })
    if not committed then return "exact offhand commit rejected without a player unit" end
    saved = LA_PERSIST.get_saved_offhands()
    rec = saved and saved[bid] and saved[bid][hand]
    if not (rec and rec.unit_path == "units/rt/dual_left"
            and rec.vanilla_key == "rt_dual_skin"
            and rec.armoury_key == nil) then
        LA_PERSIST.clear_offhand(bid, hand)
        return "saved native/CWV hand mesh did not read back"
    end
    LA_PERSIST.clear_offhand(bid, hand)
end)

-- #520: hat/outfit persistence module roundtrip (save/read/clear). The
-- careers section sat empty for weeks because no writer ever landed - this
-- locks the module API itself.
_rt_register("cos_la_cosmetic_persistence_roundtrip", function()
    if not (LA_PERSIST and LA_PERSIST.save_cosmetic) then return "cosmetic API missing" end
    local career, slot, item = "rt_fake_career", "slot_hat", "rt_fake_item_LA_rt"
    LA_PERSIST.save_cosmetic(career, slot, item)
    if LA_PERSIST.get_saved_cosmetic(career, slot) ~= item then
        LA_PERSIST.clear_cosmetic(career, slot)
        return "saved cosmetic did not read back"
    end
    if type(LA_PERSIST.get_all_saved_cosmetics) ~= "function"
        or not LA_PERSIST.get_all_saved_cosmetics()[career]
    then
        LA_PERSIST.clear_cosmetic(career, slot)
        return "get_all_saved_cosmetics missing entry"
    end
    LA_PERSIST.clear_cosmetic(career, slot)
    if LA_PERSIST.get_saved_cosmetic(career, slot) ~= nil then
        return "cleared cosmetic still present"
    end
end)

-- #25: cold-load persistence contract. The two roundtrip checks above only
-- exercise the module's process-local mirror - they stay green when the VMF
-- write, the cold _load(), or a restore consumer is unwired, which is exactly
-- the #25/#376 restart-regression class. This check seeds all three record
-- classes with fake identities, discards the process mirror and reloads from
-- the VMF setting (VMF deep-clones table settings on set AND get - vmf
-- settings.lua:54/74 via table.clone, foundation/scripts/util/table.lua:31 -
-- so the reload can only see what _persist actually wrote), then drives the
-- real cold-start restore consumers:
--   careers  -> LA_PERSIST.restore_for_player delivering into
--               CosmeticUtils.update_cosmetic_slot (spawn restore path)
--   illusion -> the shared exact-instance skin resolver (_cos_active_skin)
--   offhands -> mod._la_restore_offhand_selections reading the persisted store
-- and proves exact-instance/career independence plus a cleanup that leaves
-- the stored setting identical for every non-fake record. It fails when the
-- disk write, the cold read, or any of the three consumers is disconnected.
_rt_register("cos_la_cold_load_contract_25", function()
    if not (LA_PERSIST and LA_PERSIST._rt_cold_reload and LA_PERSIST.save_cosmetic
            and LA_PERSIST.save_illusion and LA_PERSIST.save_offhand) then
        return "persistence cold-reload API missing"
    end
    if type(LA_PERSIST.restore_for_player) ~= "function"
            or type(mod._la_restore_offhand_selections) ~= "function"
            or type(ACTIVE_SKIN) ~= "function" then
        return "cold-start restore consumer missing"
    end
    local CosmeticUtils = rawget(_G, "CosmeticUtils")
    if not (CosmeticUtils and type(CosmeticUtils.update_cosmetic_slot) == "function") then
        return "CosmeticUtils.update_cosmetic_slot missing (spawn restore sink)"
    end

    local career, other_career = "rt_cold_career", "rt_cold_career_other"
    local hat = "rt_cold_hat_LA"
    local bid_a, bid_b, bid_c = "rt_cold_bid_A", "rt_cold_bid_B", "rt_cold_bid_C"
    local skin_a, skin_b = "rt_cold_skin_A", "rt_cold_skin_B"
    local hand = "left_hand_unit"

    local function section_eq(a, b)
        a, b = a or {}, b or {}
        for k, v in pairs(a) do
            local w = b[k]
            if type(v) == "table" then
                if type(w) ~= "table" or not section_eq(v, w) then return false end
            elseif v ~= w then return false end
        end
        for k in pairs(b) do if a[k] == nil then return false end end
        return true
    end

    local function cleanup()
        LA_PERSIST.clear_cosmetic(career, "slot_hat")
        LA_PERSIST.clear_illusion(bid_a)
        LA_PERSIST.clear_illusion(bid_b)
        LA_PERSIST.clear_offhand(bid_a, hand)
        LA_PERSIST.clear_offhand(bid_b, hand)
        LA_PERSIST._rt_cold_reload()
    end

    -- Scrub residue a previously aborted run may have left, THEN snapshot the
    -- stored setting (VMF get returns a deep clone) as the restore target.
    cleanup()
    local before = mod:get("la_persisted_equips")

    -- SEED: one career cosmetic, two primary illusions, and two offhand mesh
    -- picks on distinct same-type instances; bid_c is the untouched control.
    LA_PERSIST.save_cosmetic(career, "slot_hat", hat)
    LA_PERSIST.save_illusion(bid_a, skin_a)
    LA_PERSIST.save_illusion(bid_b, skin_b)
    LA_PERSIST.save_offhand(bid_a, hand, nil, "rt_cold_vanilla", "units/rt/cold_left_a")
    LA_PERSIST.save_offhand(bid_b, hand, nil, "rt_cold_vanilla", "units/rt/cold_left_b")
    pcall(printf, "[cos:25] COLD-LOAD seeded career=1 illusions=2 offhands=2 control=%s", bid_c)

    -- COLD RELOAD: discard the process mirror, re-read the VMF setting.
    local reload_ok, reload_err = pcall(LA_PERSIST._rt_cold_reload)
    if not reload_ok then cleanup(); return "cold reload errored: " .. tostring(reload_err) end

    -- The records must have crossed the write+read boundary.
    if LA_PERSIST.get_saved_cosmetic(career, "slot_hat") ~= hat then
        cleanup(); return "career cosmetic lost across cold reload (write or load broken)"
    end
    if LA_PERSIST.get_saved_illusion(bid_a) ~= skin_a
            or LA_PERSIST.get_saved_illusion(bid_b) ~= skin_b then
        cleanup(); return "illusion lost across cold reload (write or load broken)"
    end
    if LA_PERSIST.get_saved_illusion(bid_c) ~= nil then
        cleanup(); return "control instance inherited an illusion"
    end
    local oa = LA_PERSIST.get_saved_offhands_for(bid_a)
    local ob = LA_PERSIST.get_saved_offhands_for(bid_b)
    if not (oa and oa[hand] and oa[hand].unit_path == "units/rt/cold_left_a"
            and ob and ob[hand] and ob[hand].unit_path == "units/rt/cold_left_b") then
        cleanup(); return "offhand exact-instance records lost or merged across cold reload"
    end
    if LA_PERSIST.get_saved_offhands_for(bid_c) ~= nil then
        cleanup(); return "control instance inherited an offhand"
    end

    -- CONSUMER 1 (careers): the spawn restore path must deliver the reloaded
    -- record into CosmeticUtils.update_cosmetic_slot for the exact career
    -- only. Probe players are tagged so every real call passes through to the
    -- live function unchanged during the swap window.
    local delivered = {}
    local real_update = CosmeticUtils.update_cosmetic_slot
    CosmeticUtils.update_cosmetic_slot = function(player, slot, item_name, skin_name)
        if player and player.__rt_cold_probe then
            delivered[#delivered + 1] = { slot = slot, item = item_name }
            return
        end
        return real_update(player, slot, item_name, skin_name)
    end
    local probe = { __rt_cold_probe = true, career_name = function() return career end }
    local other = { __rt_cold_probe = true, career_name = function() return other_career end }
    local applied = LA_PERSIST.restore_for_player(probe)
    local applied_other = LA_PERSIST.restore_for_player(other)
    CosmeticUtils.update_cosmetic_slot = real_update
    if applied ~= 1 or #delivered ~= 1
            or delivered[1].slot ~= "slot_hat" or delivered[1].item ~= hat then
        cleanup(); return "spawn restore did not deliver the reloaded career cosmetic"
    end
    if applied_other ~= 0 or #delivered ~= 1 then
        cleanup(); return "career cosmetic leaked onto a different career"
    end

    -- CONSUMER 2 (illusion): the shared exact-instance skin resolver must
    -- restore each saved instance; the control keeps its own skin.
    if ACTIVE_SKIN({}, bid_a) ~= skin_a or ACTIVE_SKIN({}, bid_b) ~= skin_b then
        cleanup(); return "exact-instance skin resolver did not read the reloaded illusion"
    end
    if ACTIVE_SKIN({ skin = "rt_cold_control" }, bid_c) ~= "rt_cold_control" then
        cleanup(); return "control instance did not keep its own skin"
    end

    -- CONSUMER 3 (offhands): the one-shot boot restore must read the reloaded
    -- persisted store; unresolvable fake instances must NOT leak selections.
    -- The store read is observed through a pass-through wrapper that serves
    -- only the fake instances, so the user's real records are not re-restored
    -- mid-session and the drive stays deterministic.
    local latch_done = mod._la_offhand_restore_done
    local latch_retry = mod._la_offhand_restore_retry_at
    local latch_deadline = mod._la_offhand_restore_deadline
    local latch_summary = mod._la_offhand_restore_last_summary
    local latch_rebroadcast = mod._la_self_rebroadcast_pending
    local read_count = 0
    local real_get = LA_PERSIST.get_saved_offhands
    LA_PERSIST.get_saved_offhands = function(...)
        read_count = read_count + 1
        local all = real_get(...) or {}
        return { [bid_a] = all[bid_a], [bid_b] = all[bid_b] }
    end
    mod._la_offhand_restore_done = nil
    mod._la_offhand_restore_retry_at = nil
    mod._la_offhand_restore_deadline = nil
    local drive_ok, drive_err = pcall(mod._la_restore_offhand_selections)
    LA_PERSIST.get_saved_offhands = real_get
    mod._la_offhand_restore_done = latch_done
    mod._la_offhand_restore_retry_at = latch_retry
    mod._la_offhand_restore_deadline = latch_deadline
    mod._la_offhand_restore_last_summary = latch_summary
    mod._la_self_rebroadcast_pending = latch_rebroadcast
    if not drive_ok then cleanup(); return "offhand restore errored: " .. tostring(drive_err) end
    if read_count < 1 then
        cleanup(); return "offhand restore did not read the persisted store"
    end
    if OFFHAND_SELECTION and (OFFHAND_SELECTION[bid_a] or OFFHAND_SELECTION[bid_b]) then
        OFFHAND_SELECTION[bid_a] = nil
        OFFHAND_SELECTION[bid_b] = nil
        cleanup(); return "unresolvable fake instance leaked into live offhand selection"
    end

    -- CLEANUP: clears must also survive a cold reload, and the stored setting
    -- must return to its pre-check content for every non-fake record.
    cleanup()
    if LA_PERSIST.get_saved_cosmetic(career, "slot_hat") ~= nil
            or LA_PERSIST.get_saved_illusion(bid_a) ~= nil
            or LA_PERSIST.get_saved_offhands_for(bid_b) ~= nil then
        return "fake records survived cleanup cold reload"
    end
    local after = mod:get("la_persisted_equips")
    for _, section in ipairs({ "careers", "illusions", "offhands" }) do
        if not section_eq(before and before[section], after and after[section]) then
            return "cleanup changed pre-existing persisted state (" .. section .. ")"
        end
    end
    pcall(printf, "[cos:25] COLD-LOAD PASS mirror-discard survived; career+illusion+offhand consumers delivered; control clean")
end)

end

return M
