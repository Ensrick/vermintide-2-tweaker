local mod = get_mod("cosmetics_tweaker")

-- #485: local, modded-realm access to every authored weapon pose for the
-- currently wielded weapon. Vanilla builds this wheel solely from the backend's
-- unlocked_weapon_poses mirror. We replace only that gathered result; no
-- backend entitlement, loadout, RPC, or ItemMasterList entry is mutated.

local Policy = mod._cos_weapon_pose_policy
local catalog
local unsupported = Policy.new_unsupported_ledger()

local function setting_on()
    return mod:get("cos_unlock_weapon_poses") == true
end

local function realm_untrusted()
    local sd = rawget(_G, "script_data")
    return (sd and sd["eac-untrusted"] == true) and true or false
end

local function enabled()
    return setting_on() and realm_untrusted()
end

local function get_catalog()
    if not catalog then
        catalog = Policy.build_catalog(rawget(_G, "ItemMasterList"))
    end
    return catalog
end

local function poses_for(parent_item)
    return Policy.for_parent(get_catalog(), parent_item)
end

-- #485: one truth-table walk per gather. Rows are only resolved (and the
-- catalog only built) once realm AND setting admit authored output.
local function decision_for(parent_item)
    local on, untrusted = setting_on(), realm_untrusted()
    if not (on and untrusted) then
        return Policy.decide(on, untrusted, nil), nil
    end
    local rows = poses_for(parent_item)
    return Policy.decide(on, untrusted, rows), rows
end

-- The issue requests a fallback for weapons without authored icons. Reusing
-- another weapon's package before its animation/icon compatibility is known
-- would be speculative, so unsupported parents keep vanilla behavior and this
-- captures the exact gap ONCE per parent, at most MAX_UNSUPPORTED_RECORDS
-- parents per module generation. /cos_485_diag prints the same ledger.
local function note_unsupported(parent_item)
    local outcome = Policy.record_unsupported(unsupported, parent_item)
    if outcome ~= "record" then return false end
    pcall(printf, "[cos:485] no authored pose catalog parent=%s fallback=deferred record=%d/%d",
        parent_item, unsupported.recorded, unsupported.cap)
    return true
end

local function unsupported_summary()
    return Policy.unsupported_summary(unsupported)
end

-- Read-only seam for the #485 diagnostic command in _cos_diagnostics.lua,
-- which loads after the entry creates mod._cos.
mod._cos_weapon_pose_evidence = { summary = unsupported_summary }

-- Grep-verified singleton in Cosmetics: no other hook targets either method.
mod:hook("SocialWheelUI", "_gather_weapon_poses_by_parent_item", function(func, self, parent_item)
    local decision, rows = decision_for(parent_item)
    if decision == "authored" then return rows end
    if decision == "vanilla-unsupported-parent" then
        note_unsupported(parent_item)
    end
    return func(self, parent_item)
end)

-- Force a live wheel rebuild when the option changes; otherwise vanilla's
-- early-return sees the same wielded item and keeps the stale page contents.
-- Policy.rebuild_armed arms exactly once per flip and then defers to vanilla.
mod:hook("SocialWheelUI", "_is_dirty", function(func, self, parent_item)
    if Policy.rebuild_armed(self, "_cos485_pose_unlock_state", enabled()) then
        return true
    end
    return func(self, parent_item)
end)

local M = {
    policy = Policy,
    enabled = enabled,
    poses_for = poses_for,
    decision_for = decision_for,
    note_unsupported = note_unsupported,
    unsupported_summary = unsupported_summary,
    marker = "social_wheel_authored_catalog_485",
}

-- Called by _cos_runtime_checks.lua once the command owner exists; this module
-- loads before that owner, so it cannot register at file scope.
function M.install_checks(register)
    -- #485: the check must EXECUTE the production catalog and decision table, not
    -- merely prove the seams exist - a marker-only check still passed after the
    -- authored rows, the fallback boundary, or the rebuild pulse regressed.
    register("issue485_authored_weapon_poses_local_only", function()
        if not M or M.marker ~= "social_wheel_authored_catalog_485" then
            return "weapon-pose module marker missing"
        end
        local policy = M.policy
        if not policy or type(policy.build_catalog) ~= "function"
            or type(policy.for_parent) ~= "function"
            or type(policy.decide) ~= "function"
            or type(policy.validate_catalog) ~= "function"
            or type(policy.rebuild_armed) ~= "function" then
            return "weapon-pose catalog policy incomplete"
        end
        local widgets = require("scripts/mods/cosmetics_tweaker/cosmetics_tweaker_data").options.widgets
        local found = false
        local function walk(rows)
            for _, row in ipairs(rows or {}) do
                if row.setting_id == "cos_unlock_weapon_poses" then found = true end
                if row.sub_widgets then walk(row.sub_widgets) end
            end
        end
        walk(widgets)
        if not found then return "cos_unlock_weapon_poses setting missing" end
        local cls = rawget(_G, "SocialWheelUI")
        if not cls or type(cls._gather_weapon_poses_by_parent_item) ~= "function" then
            return "SocialWheelUI pose gather seam missing"
        end
        -- Execute the PRODUCTION catalog against the live authored rows:
        -- exact-parent complete, deterministic, animation-backed, no master writes.
        local iml = rawget(_G, "ItemMasterList")
        if type(iml) ~= "table" then return "ItemMasterList unavailable" end
        local catalog = policy.build_catalog(iml)
        local parents, rows_total = 0, 0
        for _, rows in pairs(catalog) do
            parents = parents + 1
            rows_total = rows_total + #rows
        end
        if parents == 0 then
            return "production catalog is empty (no authored weapon_pose rows)"
        end
        local violation = policy.validate_catalog(catalog, iml)
        if violation then return "production catalog violation: " .. violation end
        local rebuilt = policy.build_catalog(iml)
        for parent, rows in pairs(catalog) do
            local rrows = rebuilt[parent]
            if type(rrows) ~= "table" or #rrows ~= #rows then
                return "rebuild changed catalog shape for " .. tostring(parent)
            end
            for i = 1, #rows do
                if rrows[i].ItemId ~= rows[i].ItemId then
                    return "rebuild is not deterministic for " .. tostring(parent)
                end
            end
        end
        -- Invalid and cross-parent rows must be rejected by the same builder.
        local probe_master = {
            rt485_valid_b = { item_type = "weapon_pose", parent = "rt485_parent",
                pose_index = 2, data = { anim_event = "rt485_anim_b" } },
            rt485_valid_a = { item_type = "weapon_pose", parent = "rt485_parent",
                pose_index = 1, data = { anim_event = "rt485_anim_a" } },
            rt485_no_anim = { item_type = "weapon_pose", parent = "rt485_parent",
                pose_index = 3, data = {} },
            rt485_no_index = { item_type = "weapon_pose", parent = "rt485_parent",
                data = { anim_event = "rt485_anim_x" } },
            rt485_not_pose = { item_type = "weapon_skin", parent = "rt485_parent",
                pose_index = 4, data = { anim_event = "rt485_anim_y" } },
            rt485_other = { item_type = "weapon_pose", parent = "rt485_other",
                pose_index = 1, data = { anim_event = "rt485_anim_z" } },
        }
        local probe_rows = policy.for_parent(policy.build_catalog(probe_master), "rt485_parent")
        if not probe_rows or #probe_rows ~= 2
            or probe_rows[1].ItemId ~= "rt485_valid_a"
            or probe_rows[2].ItemId ~= "rt485_valid_b" then
            return "builder admitted an invalid or cross-parent row"
        end
        if probe_master.rt485_valid_a.backend_id ~= nil then
            return "builder stamped backend identity onto a master row"
        end
        -- The three realm/setting decisions stay distinct, and unsupported
        -- parents resolve to their own vanilla outcome.
        local d_authored = policy.decide(true, true, probe_rows)
        local d_off = policy.decide(false, true, probe_rows)
        local d_official = policy.decide(true, false, probe_rows)
        local d_unsupported = policy.decide(true, true, nil)
        if d_authored ~= "authored"
            or d_off ~= "vanilla-setting-off"
            or d_official ~= "vanilla-official-realm"
            or d_unsupported ~= "vanilla-unsupported-parent"
            or d_off == d_official then
            return "realm/setting/support decisions are not distinct"
        end
        if type(M.decision_for) ~= "function"
            or type(M.note_unsupported) ~= "function"
            or type(M.unsupported_summary) ~= "function"
            or type(policy.new_unsupported_ledger) ~= "function"
            or type(policy.record_unsupported) ~= "function" then
            return "gather decision seams missing"
        end
        -- Unsupported parents record ONE identity each under a hard total cap. A
        -- scratch ledger proves the policy so the live evidence ledger stays clean.
        local scratch = policy.new_unsupported_ledger(2)
        if policy.record_unsupported(scratch, "rt485_a") ~= "record"
            or policy.record_unsupported(scratch, "rt485_a") ~= "duplicate"
            or policy.record_unsupported(scratch, "rt485_b") ~= "record"
            or policy.record_unsupported(scratch, "rt485_c") ~= "capped"
            or policy.record_unsupported(scratch, "rt485_c") ~= "duplicate"
            or scratch.recorded ~= 2 or scratch.suppressed ~= 1 then
            return "unsupported-parent evidence is not deduplicated under a hard cap"
        end
        local cap = policy.MAX_UNSUPPORTED_RECORDS
        if type(cap) ~= "number" or cap < 1 or cap > 64
            or policy.new_unsupported_ledger(cap + 1000).cap ~= cap then
            return "unsupported-parent evidence cap is missing or unbounded"
        end
        local live = M.unsupported_summary()
        if type(live) ~= "table" or live.cap ~= cap
            or type(live.recorded) ~= "number" or live.recorded > cap then
            return "live unsupported-parent ledger exceeds its cap"
        end
        -- Exactly one armed wheel rebuild per option flip.
        local holder = {}
        if policy.rebuild_armed(holder, "_cos485_pose_unlock_state", true) ~= true
            or policy.rebuild_armed(holder, "_cos485_pose_unlock_state", true) ~= false
            or policy.rebuild_armed(holder, "_cos485_pose_unlock_state", false) ~= true
            or policy.rebuild_armed(holder, "_cos485_pose_unlock_state", false) ~= false then
            return "option flip did not arm exactly one wheel rebuild"
        end
        pcall(printf, "[cos:485] catalog executed parents=%d rows=%d decisions=distinct rebuild=one-shot",
            parents, rows_total)
    end)
end

return M
