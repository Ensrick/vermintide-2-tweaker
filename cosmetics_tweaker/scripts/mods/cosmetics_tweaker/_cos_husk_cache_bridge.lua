-- _cos_husk_cache_bridge.lua -- husk-cache dual-namespace mirror (#154).
--
-- WHY: the husk render surfaces read the LA equip store by the wielded item's
-- TEMPLATE only (`_la_equips_by_peer[wearer][item_data.template]` in the
-- BackendUtils.get_item_units mesh gate and `stored_key == wielded_template`
-- in the post-wield repaint), but the CosmeticUtils.update_cosmetic_slot
-- illusion emit stores entries under the cosmetic SLOT name ("slot_melee" /
-- "slot_ranged"). Those slot-keyed entries are stored yet UNREACHABLE, so a
-- cross-character weapon slot always logs
--   [cos:sync] ... decision=no-op(cache-or-kind-miss) cache_entry=false
-- and the wearer's cosmetic never renders on teammates (issue #154, log
-- sweep 2026-07-18). Native weapons masked the same miss because the vanilla
-- wire still carries their skin; cross-char slots have it wire-substituted
-- away (#371 family), leaving this store as the only delivery path.
--
-- FIX: at the receive/store edge (every apply funnels through
-- mod._la_reconcile on every peer - recv/retry/replay/transition/husk-wield,
-- the #264 single entry point), mirror a slot-keyed weapon-side entry under
-- the wearer's live equipped TEMPLATE for that slot, then reconcile the
-- template key too. The mirror stores the SAME entry table (identity alias)
-- so the revert path can sweep every alias, mirroring the #234/#264/#268
-- proven shapes (store -> reconcile -> gated pulse; wearer-scoped only).
-- A direct template-keyed write (EMIT-ON-EXIT dual-namespace bake) always
-- wins over a mirror: the mirror only fills an empty key or replaces its
-- own previous mirror, never a direct write.
--
-- Owned by: cosmetics_tweaker.lua (attach() wraps mod._la_reconcile and
-- mod._la_apply_revert_recv AFTER both are defined). Pure helpers below the
-- attach seam are offline-tested by qa/lua/tests/test_cos_husk_cache_bridge.lua.

local M = {}

-- Wield-slot namespace the update_cosmetic_slot illusion emit uses. Only
-- these keys can alias a weapon template; attachment slots (slot_hat /
-- slot_skin) are read by their own husk paths and must never mirror.
M.WIELD_SLOTS = {
    slot_melee = true,
    slot_ranged = true,
    slot_career_skill_weapon = true,
}

-- Pure: the wearer's live equipped template for a wield slot.
-- equipment.slots[slot_name].item_data.template is the same field the husk
-- repaint reads (cosmetics_tweaker.lua husk _wield_slot wrap).
function M.wielded_template(inventory_ext, slot_name)
    local equipment = inventory_ext and inventory_ext._equipment
    local slot_data = equipment and equipment.slots and equipment.slots[slot_name]
    local item_data = slot_data and slot_data.item_data
    local template = item_data and item_data.template
    if type(template) ~= "string" or template == "" then return nil end
    return template
end

-- Pure: mirror store[wearer][slot_name] under [template] (same table ref).
-- book tracks mirror provenance so a later mirror may replace its own prior
-- write but never a direct template-keyed emit. vstore is the #416 parallel
-- vanilla-mesh store; the mirrored key gets the same (wearer, slot, hand)
-- mutual exclusion the direct store write performs.
-- Returns "mirrored" | "already" | "direct-write-wins" | nil (no entry /
-- bad namespace / no template).
function M.mirror(store, vstore, book, wearer, slot_name, template)
    if not (store and wearer and slot_name and template) then return nil end
    if template == slot_name or not M.WIELD_SLOTS[slot_name] then return nil end
    local slots = store[wearer]
    local entry = slots and slots[slot_name]
    if type(entry) ~= "table" then return nil end
    if not (entry.kind == "offhand" or entry.kind == "illusion") then return nil end
    local existing = slots[template]
    if existing == entry then return "already" end
    local book_key = tostring(wearer) .. "|" .. tostring(template)
    if existing ~= nil and (not book or book[book_key] == nil) then
        return "direct-write-wins"
    end
    slots[template] = entry
    if book then book[book_key] = slot_name end
    local vslot = vstore and vstore[wearer] and vstore[wearer][template]
    if vslot and entry.hand_field then vslot[entry.hand_field] = nil end
    return "mirrored"
end

-- Pure: delete every alias key in store[wearer] holding the identical entry
-- table (revert support - the revert receiver deletes only [slot_name]).
-- Identity comparison can never over-delete an unrelated entry.
function M.sweep_aliases(store, wearer, entry_ref, book)
    local slots = store and store[wearer]
    if not (slots and entry_ref) then return 0 end
    local removed = 0
    for key, value in pairs(slots) do
        if value == entry_ref then
            slots[key] = nil
            removed = removed + 1
            if book then book[tostring(wearer) .. "|" .. tostring(key)] = nil end
        end
    end
    return removed
end

-- Engine-side template resolution for the wearer peer's HUMAN player.
-- player_from_peer_id defaults local_player_id 1 = the human; bots live at
-- 2+ [src: scripts/managers/player/player_manager.lua:463-470] - the #268
-- wearer-scoping rule.
local function _resolve_template(managers, script_unit, wearer, slot_name)
    local ok, template = pcall(function()
        local pm = managers and managers.player
        local player = pm and pm.player_from_peer_id
            and pm:player_from_peer_id(wearer)
        local unit = player and player.player_unit
        local inv = unit and script_unit and script_unit.has_extension
            and script_unit.has_extension(unit, "inventory_system")
        return M.wielded_template(inv, slot_name)
    end)
    if not ok then return nil end
    return template
end

-- Wrap the two mod seams. deps: { managers = fn() -> Managers,
-- script_unit = ScriptUnit, probe = PROBE|nil, printf = printf|nil }.
-- Returns true when both seams were wrapped.
function M.attach(mod, deps)
    deps = deps or {}
    local managers_fn = deps.managers or function() return rawget(_G, "Managers") end
    local script_unit = deps.script_unit or rawget(_G, "ScriptUnit")
    local probe = deps.probe
    local printf_fn = deps.printf
    local orig_reconcile = mod._la_reconcile
    local orig_revert = mod._la_apply_revert_recv
    if type(orig_reconcile) ~= "function" or type(orig_revert) ~= "function" then
        if printf_fn then
            printf_fn("[cos:154] husk-cache bridge NOT attached (reconcile=%s revert=%s)",
                tostring(orig_reconcile ~= nil), tostring(orig_revert ~= nil))
        end
        return false
    end
    mod._cos_husk_mirrored = mod._cos_husk_mirrored or {}

    mod._la_reconcile = function(wearer, slot_name, tag, allow_pulse)
        local mirrored_template = nil
        if wearer and M.WIELD_SLOTS[slot_name] then
            local template = _resolve_template(managers_fn(), script_unit,
                wearer, slot_name)
            if template then
                local outcome = M.mirror(mod._la_equips_by_peer,
                    mod._offhand_mesh_by_peer, mod._cos_husk_mirrored,
                    wearer, slot_name, template)
                if outcome == "mirrored" or outcome == "already" then
                    mirrored_template = template
                end
                if outcome == "mirrored" then
                    local entry = mod._la_equips_by_peer[wearer]
                        and mod._la_equips_by_peer[wearer][template]
                    local line = string.format(
                        "peer=husk event=cache-mirror wearer=%s slot=%s -> template=%s kind=%s key=%s",
                        tostring(wearer), tostring(slot_name), tostring(template),
                        tostring(entry and entry.kind),
                        tostring(entry and entry.armoury_key))
                    if probe then
                        probe.emit("cos:sync", "mirror/" .. tostring(wearer)
                            .. "/" .. tostring(slot_name) .. "/" .. tostring(template), line)
                    elseif printf_fn then
                        printf_fn("[cos:sync] %s", line)
                    end
                end
            end
        end
        local applied, reason = orig_reconcile(wearer, slot_name, tag, allow_pulse)
        if mirrored_template then
            -- Re-drive under the item-matchable key: the husk mesh gate and
            -- the weapon-identity guard both match templates, never slots.
            local t_applied, t_reason = orig_reconcile(wearer, mirrored_template,
                tag, allow_pulse)
            if t_applied then return t_applied, t_reason end
        end
        return applied, reason
    end

    mod._la_apply_revert_recv = function(wearer, slot_name, kind, vanilla_key, hand_field)
        local store = mod._la_equips_by_peer
        local entry_ref = store and store[wearer] and store[wearer][slot_name]
        orig_revert(wearer, slot_name, kind, vanilla_key, hand_field)
        if entry_ref then
            local removed = M.sweep_aliases(store, wearer, entry_ref,
                mod._cos_husk_mirrored)
            if removed > 0 and printf_fn then
                printf_fn("[cos:154] REVERT swept %d mirrored alias(es) wearer=%s slot=%s",
                    removed, tostring(wearer), tostring(slot_name))
            end
        end
    end
    return true
end

return M
