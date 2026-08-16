-- _gut_reset_presentation_core.lua -- pure reconcile planning for the post-DEFAULT
-- active-career presentation refresh (issue #1033).
--
-- After a Mod Tweaker Equipment DEFAULT, reset_modded_loadouts durably rewrites the
-- modded loadout store and dirtifies the backend interfaces, but the already-spawned
-- keep unit keeps rendering its old weapons/attachments/skin. Vanilla refreshes a
-- changed slot through exactly one of three paths: melee/ranged through the inventory
-- extension, hat/jewelry through the attachment extension (the hero-view equip request
-- dispatch, hero_view_state_overview.lua:697-714), and a skin change through one
-- profile respawn (hero_view_state_overview.lua:1157-1161 -> ingame_ui.lua:1290-1305).
-- This core owns the pure decisions: which slot rides which vanilla path, whether the
-- skin change forces the respawn, and the desired-vs-live diff that bounds the refresh
-- to slots the reset actually changed. Engine reads/writes live in
-- _gut_reset_presentation.lua; keep this file free of VMF/game globals so the offline
-- harness can drive it.
--
-- Owned by: gui_tweaker_dev.lua entry point (via _gut_reset_presentation.lua).
-- Consumed via: mod:dofile.

local C = {}

C.ROUTE_INVENTORY = "inventory"    -- SimpleInventoryExtension.create_equipment_in_slot (simple_inventory_extension.lua:1372)
C.ROUTE_ATTACHMENT = "attachment"  -- PlayerUnitAttachmentExtension.create_attachment_in_slot (player_unit_attachment_extension.lua:241)
C.ROUTE_RESPAWN = "respawn"        -- IngameUI:respawn profile request (ingame_ui.lua:1290-1305)
C.ROUTE_NONE = "none"              -- pure UI surface; consumed from the dirtified backend on next read

-- Route per canonical loadout slot, mirroring the vanilla equip-request dispatch
-- (hero_view_state_overview.lua:706-712) and the skin sync respawn (:1157-1161).
C.SLOT_ROUTES = {
    slot_melee = C.ROUTE_INVENTORY,
    slot_ranged = C.ROUTE_INVENTORY,
    slot_hat = C.ROUTE_ATTACHMENT,
    slot_necklace = C.ROUTE_ATTACHMENT,
    slot_ring = C.ROUTE_ATTACHMENT,
    slot_trinket_1 = C.ROUTE_ATTACHMENT,
    slot_skin = C.ROUTE_RESPAWN,
    slot_frame = C.ROUTE_NONE,
    slot_pose = C.ROUTE_NONE,
}

-- The slots the per-slot equip reconcile walks (deterministic order for receipts).
C.EQUIP_SLOTS = {
    "slot_melee", "slot_ranged", "slot_hat", "slot_necklace", "slot_ring", "slot_trinket_1",
}

-- One profile respawn only when the skin identity provably changed: both reads must
-- have succeeded (a nil read is "unknown", never a respawn trigger).
function C.skin_changed(before_skin, after_skin)
    return type(before_skin) == "string" and type(after_skin) == "string"
        and before_skin ~= after_skin
end

-- The reconcile may only touch the live unit at a safe keep boundary; anywhere else
-- the durable reset defers (issue #1033 fallback 3).
function C.should_defer(in_keep, unit_alive)
    return not (in_keep == true and unit_alive == true)
end

-- Per-slot decision. A desired id that does not resolve in the masterlist right now is
-- a SKIP, never a destroy (issues #375/#387 non-destructive doctrine); an empty desired
-- slot is a SKIP (jewelry may deliberately stay empty; nothing safe to equip). Matching
-- ids are already presented; matching item keys with no live id also count as presented
-- (spawn paths may not stamp backend_id). Differing ids re-equip even when the item key
-- matches: the reset may have restored an official instance with different properties.
function C.plan_slot(desired_id, desired_key, live_id, live_key)
    if desired_id == nil then return "skip-empty-desired" end
    if desired_key == nil then return "skip-unresolvable" end
    if live_id ~= nil then
        if live_id == desired_id then return "skip-same" end
        return "equip"
    end
    if live_key ~= nil and live_key == desired_key then return "skip-same" end
    return "equip"
end

-- Full desired-vs-live plan over C.EQUIP_SLOTS. Returns a table with the ordered
-- `actions` array ({ slot, backend_id, route }) plus bounded skip counters.
function C.plan(desired_ids, desired_keys, live_ids, live_keys)
    desired_ids = type(desired_ids) == "table" and desired_ids or {}
    desired_keys = type(desired_keys) == "table" and desired_keys or {}
    live_ids = type(live_ids) == "table" and live_ids or {}
    live_keys = type(live_keys) == "table" and live_keys or {}
    local plan = { actions = {}, skipped_same = 0, skipped_unresolvable = 0, skipped_empty = 0 }
    for i = 1, #C.EQUIP_SLOTS do
        local slot = C.EQUIP_SLOTS[i]
        local verdict = C.plan_slot(desired_ids[slot], desired_keys[slot], live_ids[slot], live_keys[slot])
        if verdict == "equip" then
            plan.actions[#plan.actions + 1] = {
                slot = slot,
                backend_id = desired_ids[slot],
                route = C.SLOT_ROUTES[slot],
            }
        elseif verdict == "skip-same" then
            plan.skipped_same = plan.skipped_same + 1
        elseif verdict == "skip-unresolvable" then
            plan.skipped_unresolvable = plan.skipped_unresolvable + 1
        else
            plan.skipped_empty = plan.skipped_empty + 1
        end
    end
    return plan
end

return C
